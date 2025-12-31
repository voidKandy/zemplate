const std = @import("std");
const root = @import("root.zig");
const ast = @import("ast.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Lexer = @import("Lexer.zig");
const Type = std.builtin.Type;
const Token = @import("Token.zig");
const log = std.log.scoped(.Parser);
const Error = @import("root.zig").Error;
const util = @import("util.zig");
const allocPrint = std.fmt.allocPrint;
/// TO BE REMOVED
// const SerializeOptions = util.SerializeOptions;

arena: std.heap.ArenaAllocator,
writer: std.Io.Writer.Allocating,
errors: ArrayList(u8),

lexer: Lexer,

json_options: std.json.Stringify.Options,

current_token: Token,
peek_token: Token,
prev_token: ?Token = null,

const Self = @This();

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
        \\ --- PARSER --- 
        \\ current token: {any}
        \\ previous token: {any}
        \\ arena usage: {d}
        \\ errors:
        \\ {s}
    , .{
        self.arena.queryCapacity(),
        self.current_token,
        self.prev_token,
        self.errors.items,
    });
}

pub fn init(
    a: Allocator,
    lexer: Lexer,
    json_opts: ?std.json.Stringify.Options,
) Allocator.Error!Self {
    // maybe rmove?
    if (lexer.pos != 0)
        @panic("Parser initialized with Lexer with .pos != 0");
    const arena = std.heap.ArenaAllocator.init(a);
    const writer: std.Io.Writer.Allocating = .init(a);

    const current_token = lexer.nextToken();
    const peek_token = lexer.nextToken();

    return Self{
        .arena = arena,
        .writer = writer,
        .current_token = current_token,
        .peek_token = peek_token,
        .lexer = lexer,
        .json_options = json_opts orelse .{},
        .errors = try .initCapacity(arena.allocator(), 64),
    };
}

pub fn deinit(self: *Self) void {
    self.errors.deinit(self.arena.allocator());
    self.arena.deinit();
    self.writer.deinit();
    self.lexer.deinit();
}

pub fn parseProgram(self: *Self) ast.Program {
    var program = &ast.Program{};

    while (!self.current_token.typ != .eof) {
        const stmt = self.parseStatement();
        if (stmt != null) {
            program.statements.append(self.arena.allocator(), stmt);
        }
        self.progressToken();
    }
    return program;
}

fn parseStatement(self: *Self) ?ast.Statement {
    switch (self.current_token.typ) {
        .statement_open => switch (self.peek_token.typ) {
            .for_open => return .{ .variant = .{
                .@"for" = self.parseForStatement(),
            } },
            .if_open => return .{ .variant = .{
                .@"if" = self.parseIfStatement(),
            } },
            .@"else" => return .{ .variant = .{
                .@"else" = self.parseElseStatement(),
            } },
            else => {},
        },
        .expression_open => return .{ .variant = .{
            .expression = self.parseExpressionStatement(.expression_close),
        } },
        else => {},
    }

    self.emitError(
        \\ Could not parse statement that begins with token: {f}
    , .{self.current_token}) catch @panic("OOM");
}

fn parseAccessExpression(self: *Self, expected_close_token: Token.Type) ast.AccessExpression {
    if (expected_close_token != .statement_close and expected_close_token != .expression_close)
        @panic("Passed an invalid expected close token to parseAccessExpression");
    _ = self.expectPeekAndProgress(.access);
    var access = ast.AccessExpression{
        .literal = self.current_token.literal,
    };
    while (self.peek_token.typ != expected_close_token) {
        switch (self.peek_token.typ) {
            .json => {
                access.json = true;
                self.progressToken();
            },
            else => {
                self.emitError(
                    \\ Did not expect to encounter {any} between .access token and .expression_close
                , .{self.peek_token.typ}) catch @panic("OOM");
            },
        }
    }
    _ = self.expectPeekAndProgress(expected_close_token);
    return access;
}

fn parseForStatement(self: *Self) ast.ForStatement {
    _ = self.expectPeekAndProgress(.for_open);
    // for statements can ONLY have access expressions, not comparison
    const access = self.parseAccessExpression(.statement_close);

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseStatement = null;
    while (self.peek_token.typ != .for_close) {
        const statement = self.parseStatement() orelse {
            self.emitError(
                \\ Expected statement in for block
            , .{}) catch @panic("OOM");
            break;
        };

        if (statement.variant == .@"else")
            alternative = statement
        else
            body.append(self.arena.allocator(), statement);
    }

    _ = self.expectPeekAndProgress(.for_close);
    _ = self.expectPeekAndProgress(.statement_close);

    return .{
        .access = access,
        .alternative = alternative,
        .body = body.toOwnedSlice(self.arena.allocator()),
    };
}

fn parseIfStatement(self: *Self) ast.IfStatement {
    _ = self.expectPeekAndProgress(.if_open);
    const condition = self.parseExpressionStatement(.statement_close);

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseStatement = null;

    while (self.peek_token.typ != .if_close) {
        const statement = self.parseStatement() orelse {
            self.emitError(
                \\ Expected statement in for block
            , .{}) catch @panic("OOM");
            break;
        };

        if (statement.variant == .@"else")
            alternative = statement
        else
            body.append(self.arena.allocator(), statement);
    }

    _ = self.expectPeekAndProgress(.if_close);
    _ = self.expectPeekAndProgress(.statement_close);

    return .{
        .condition = condition,
        .alternative = alternative,
        .body = body.toOwnedSlice(self.arena.allocator()),
    };
}

/// Expressions can appear between
/// something following `statement_open` (for or if open) & `statement_close`
/// or
/// `expression_open` & `expression_close`
fn parseExpressionStatement(self: *Self, expected_close_token: Token.Type) ast.ExpressionStatement {
    if (!self.expectPrevious(.for_open) and !self.expectPrevious(.if_open) and !self.expectPrevious(.expression_open))
        self.emitError(
            \\ trying to parse expression statement with unexpected previous: '{s}'
        , .{if (self.prev_token) |t| @tagName(t) orelse "null"});

    switch (self.peek_token.typ) {
        .literal => {
            // const literal = self.peek_token.literal;
            _ = self.expectPeekAndProgress(.literal);
        },
        .access => return .{ .access = self.parseAccessExpression(expected_close_token) },
        else => {},
    }
}

fn progressToken(self: *Self) void {
    self.prev_token = self.current_token;
    self.current_token = self.peek_token;
    self.peek_token = self.lexer.nextToken();
}

fn expectPrevious(self: Self, expected_prev: Token.Type) bool {
    if (self.prev_token == null) return false;

    return self.prev_token.?.typ == expected_prev;
}

fn expectPeekAndProgress(self: *Self, expected_next: Token.Type) bool {
    if (self.peek_token.typ == expected_next) {
        self.progressToken();
        return true;
    }

    self.emitError(
        \\ Expected next token to be {any}, got {any} instead
    , .{ expected_next, self.peek_token }) catch @panic("OOM");
    return false;
}

fn emitError(self: *Self, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    try self.errors.append(
        self.arena.allocator(),
        try allocPrint(fmt, args),
    );
}
