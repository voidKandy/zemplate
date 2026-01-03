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
errors: ArrayList([]u8),

lexer: *Lexer,

json_options: std.json.Stringify.Options,

current_token: Token,
peek_token: Token,
prev_token: ?Token = null,

const Self = @This();

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
        \\ --- PARSER --- 
        \\ arena usage: {d}
        \\ Lexer position: {d}
        \\ current token: {f}
        \\ peek token: {f}
    , .{
        self.arena.queryCapacity(),
        self.lexer.pos,
        self.current_token,
        self.peek_token,
    });

    if (self.prev_token) |t| {
        try writer.print(
            \\
            \\ previous token: {f}
        , .{t});
    }
}

pub fn init(
    a: Allocator,
    lexer: *Lexer,
    json_opts: ?std.json.Stringify.Options,
) Allocator.Error!Self {
    // maybe rmove?
    if (lexer.pos != 0)
        @panic("Parser initialized with Lexer with .pos != 0");
    var arena = std.heap.ArenaAllocator.init(a);
    const writer: std.Io.Writer.Allocating = .init(a);

    const current_token = lexer.nextTokenSkipWhitespace();
    const peek_token = lexer.nextTokenSkipWhitespace();

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

pub fn parseProgram(self: *Self) Allocator.Error!ast.Program {
    var program = ast.Program{};

    while (!self.current_token.typ.eql(.eof)) {
        const stmt = try self.parseStatement();

        if (self.errors.items.len > 0) {
            for (self.errors.items) |e| {
                log.err(
                    \\ Parser State: {f}
                    \\ Parser Error: {s}
                , .{ self, e });
            }
            return program;
        }
        if (stmt) |s|
            try program.statements.append(self.arena.allocator(), s);

        self.progressToken();
    }

    return program;
}

fn parseStatement(self: *Self) Allocator.Error!?ast.Statement {
    switch (self.current_token.typ) {
        .statement_open => switch (self.peek_token.typ) {
            .for_open => return .{ .variant = .{
                .@"for" = try self.parseForStatement() orelse return null,
            } },
            .if_open => return .{ .variant = .{
                .@"if" = try self.parseIfStatement() orelse return null,
            } },
            .@"else" => return .{ .variant = .{
                .@"else" = try self.parseElseStatement() orelse return null,
            } },
            else => {},
        },
        .expression_open => return .{ .variant = .{
            .expression = try self.parseExpressionStatement() orelse return null,
        } },
        else => {},
    }

    self.emitError(
        \\ Could not parse statement that begins with token: {f}
    , .{self.current_token}) catch @panic("OOM");
    return null;
}

fn parseAccessExpression(self: *Self) Allocator.Error!?ast.AccessExpression {
    if (!self.expectPeekAndProgress(.access)) {
        try self.emitError("Expected to encounter an access expression", .{});
        return null;
    }
    var access = ast.AccessExpression{
        .literal = self.current_token.literal,
    };

    // when more serialization options are added, this will need to account for those
    switch (self.peek_token.typ) {
        .json => {
            access.json = true;
            self.progressToken();
        },
        else => {},
    }
    return access;
}

fn parseElseStatement(self: *Self) Allocator.Error!?ast.ElseStatement {
    if (!self.expectPeekAndProgress(.@"else")) return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    var body = ArrayList(ast.Statement).empty;
    while (self.peek_token.typ != .statement_open) {
        const statement = try self.parseStatement() orelse {
            self.emitError(
                \\ Expected statement in for block
            , .{}) catch @panic("OOM");
            return null;
        };

        try body.append(self.arena.allocator(), statement);
    }

    return .{
        .body = try body.toOwnedSlice(self.arena.allocator()),
    };
}

fn parseForStatement(self: *Self) Allocator.Error!?ast.ForStatement {
    if (!self.expectPeekAndProgress(.for_open)) return null;
    // for statements can ONLY have access expressions, not comparison
    const access = try self.parseAccessExpression() orelse return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseStatement = null;
    while (self.peek_token.typ != .for_close) {
        const statement = try self.parseStatement() orelse {
            self.emitError(
                \\ Expected statement in for block
            , .{}) catch @panic("OOM");
            return null;
        };

        if (statement.variant == .@"else")
            alternative = statement.variant.@"else"
        else
            try body.append(self.arena.allocator(), statement);
    }

    if (!self.expectPeekAndProgress(.for_close)) return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    return .{
        .access = access,
        .alternative = alternative,
        .body = try body.toOwnedSlice(self.arena.allocator()),
    };
}

fn parseIfStatement(self: *Self) Allocator.Error!?ast.IfStatement {
    if (!self.expectPeekAndProgress(.if_open)) return null;

    const condition = try self.parseExpressionStatement() orelse {
        try self.emitError("Expected to encounter a condition statement in if statement", .{});
        return null;
    };

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseStatement = null;
    while (self.peek_token.typ != .if_close) {
        const statement = try self.parseStatement() orelse {
            try self.emitError(
                \\ Expected statement in for block
            , .{});
            return null;
        };

        if (statement.variant == .@"else")
            alternative = statement.variant.@"else"
        else
            try body.append(self.arena.allocator(), statement);
    }

    if (!self.expectPeekAndProgress(.if_close)) return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    return .{
        .condition = condition,
        .alternative = alternative,
        .body = try body.toOwnedSlice(self.arena.allocator()),
    };
}

/// Expressions can appear between
/// something following `statement_open` (for or if open) & `statement_close`
/// or
/// `expression_open` & `expression_close`
fn parseExpressionStatement(self: *Self) Allocator.Error!?ast.ExpressionStatement {
    const left = blk: {
        switch (self.peek_token.typ) {
            .literal => {
                const literal_expr =
                    ast.LiteralExpression.tryFromStringLiteral(self.peek_token.literal) orelse {
                        try self.emitError(
                            \\ Failed to parse literal expression from string literal: '{s}'
                        , .{self.peek_token.literal});
                        return null;
                    };

                const left =
                    try ast.ExpressionStatement.create(self.arena.allocator(), .{ .literal = literal_expr });

                std.debug.assert(self.expectPeekAndProgress(.literal));
                break :blk left;
            },
            .access => {
                const left = try ast.ExpressionStatement.create(
                    self.arena.allocator(),
                    .{ .access = try self.parseAccessExpression() orelse return null },
                );
                break :blk left;
            },
            else => {
                try self.emitError(
                    \\ Cannot parse expression statement starting with token: {any}
                , .{self.peek_token.typ});

                return null;
            },
        }
    };

    const return_value = blk: {
        if (self.peek_token.typ.isComparison()) {
            const operator = ast.ComparisonExpression.Operator.tryFromTokenType(self.peek_token.typ).?;
            self.progressToken();
            const right = try self.parseExpressionStatement() orelse return null;
            break :blk try ast.ExpressionStatement.create(self.arena.allocator(), .{ .comparison = .{
                .operator = operator,
                .left = left,
                .right = right,
            } });
        }

        break :blk left;
    };

    switch (self.peek_token.typ) {
        .expression_close, .statement_close => |t| {
            _ = self.expectPeekAndProgress(t);
        },
        else => |t| {
            try self.emitError(
                \\ Expected Expression statement to end with .expression_close or .statement_close
                \\ Got: {any}
            , .{t});
        },
    }

    self.progressToken();

    return return_value;
}

/// Progresses token, skipping whitespace and updating prev/current/peek
fn progressToken(self: *Self) void {
    self.prev_token = self.current_token;
    self.current_token = self.peek_token;
    self.peek_token = self.lexer.nextTokenSkipWhitespace();
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
        \\ Expected next token to be {any}, got {f} instead
    , .{ expected_next, self.peek_token }) catch @panic("OOM");
    return false;
}

fn emitError(self: *Self, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    try self.errors.append(
        self.arena.allocator(),
        try allocPrint(self.arena.allocator(), fmt, args),
    );
}
