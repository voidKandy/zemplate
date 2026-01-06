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
        \\------ PARSER ------
        \\ arena usage: {d}
        \\ Lexer position: {d}
        \\ current token: {f}
        \\ peek token: {f}
        \\
    , .{
        self.arena.queryCapacity(),
        self.lexer.pos,
        self.current_token,
        self.peek_token,
    });

    if (self.prev_token) |t| {
        try writer.print(
            \\ previous token: {f}
            \\
        , .{t});
    }

    try writer.writeAll(
        \\--------------------
    );
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

const ParseError = error{ OutOfMemory, Unexpected };

pub fn logErrors(self: Self, _log: anytype) void {
    if (!@hasDecl(_log, "err") or
        !@hasDecl(_log, "warn") or
        !@hasDecl(_log, "info") or
        !@hasDecl(_log, "debug")) @panic("invalid type passed to logErrors");

    for (self.errors.items) |e| {
        _log.err("{s}", .{e});
    }
}

pub fn parseProgram(self: *Self) ParseError!ast.Program {
    var program = ast.Program{};

    while (!self.current_token.typ.eql(.eof)) {
        const stmt = try self.parseStatement();

        if (self.errors.items.len > 0) {
            return error.Unexpected;
        }

        if (stmt) |s|
            try program.statements.append(self.arena.allocator(), s);

        self.progressToken();
    }

    return program;
}

fn parseStatement(self: *Self) Allocator.Error!?ast.Statement {
    switch (self.current_token.typ) {
        .statement_open => {
            switch (self.peek_token.typ) {
                .for_open => return .{ .@"for" = try self.parseForStatement() orelse {
                    try self.emitError(
                        \\ Failed to parse for statement
                        \\{f}
                    , .{self});
                    return null;
                } },
                .if_open => return .{ .@"if" = try self.parseIfStatement() orelse {
                    try self.emitError(
                        \\ Failed to parse if statement
                        \\{f}
                    , .{self});
                    return null;
                } },
                // .@"else" => return .{ .block = try self.parseBlockStatement() orelse {
                //     try self.emitError(
                //         \\ Failed to parse block statement
                //         \\{f}
                //     , .{self});
                //     return null;
                // } },
                else => {},
            }
        },
        .expression_open => return .{ .expression = try self.parseExpressionStatement() orelse {
            try self.emitError(
                \\ Failed to parse expression statement
                \\ Parser state:
                \\ {f}
            , .{self});
            return null;
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

    while (self.peek_token.typ != .expression_close and
        self.peek_token.typ != .statement_close and !self.peek_token.typ.isComparison())
    {
        // when more serialization options are added
        // this will need to account for those
        switch (self.peek_token.typ) {
            .json => access.json = true,
            else => log.warn(
                \\ Token ignored when parsing access token: {f}
            , .{self.peek_token}),
        }
        self.progressToken();
    }

    self.progressToken();
    return access;
}

fn parseElseBlock(self: *Self, closing_tag: Token.Type) Allocator.Error!?ast.ElseBlock {
    if (!self.expectPeekAndProgress(.@"else")) return null;

    var condition: ?ast.ExpressionStatement = null;
    if (self.peek_token.typ == .if_open) {
        _ = self.expectPeekAndProgress(.if_open);
        condition = try self.parseExpressionStatement() orelse {
            try self.emitError(
                \\ Else statement contained 'if' but no condition followed
            , .{});
            return null;
        };
    } else {
        if (!self.expectPeekAndProgress(.statement_close)) return null;
        self.progressToken();
    }

    if (self.prev_token.?.typ != .statement_close) {
        try self.emitError(
            \\ Expected prev_token to be .statement_close after parsing beginning of else statement
            \\ Got: {any}
        , .{self.prev_token.?.typ});
        return null;
    }

    var body = ArrayList(ast.Statement).empty;
    while (self.peek_token.typ != closing_tag) {
        const statement = try self.parseStatement() orelse {
            try self.emitError(
                \\ Expected statement in block
            , .{});
            return null;
        };

        try body.append(self.arena.allocator(), statement);
    }

    if (self.current_token.typ != .statement_open) {
        try self.emitError(
            \\ Expected current_token to be .statement_open after parsing block
            \\ Got: {any}
        , .{self.current_token});
        return null;
    }

    // if (!self.expectPeekAndProgress(.statement_open)) return null;
    // self.progressToken();
    return .{
        .condition = condition,
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

fn parseForStatement(self: *Self) Allocator.Error!?ast.ForStatement {
    if (!self.expectPeekAndProgress(.for_open)) return null;

    // for statements can ONLY have access expressions, not comparison
    const access = try self.parseAccessExpression() orelse return null;
    self.progressToken();
    // if (!self.expectPeekAndProgress(.statement_close)) return null;

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseBlock = null;
    while (self.peek_token.typ != .for_close) {
        if (self.peek_token.typ == .@"else") {
            alternative = try self.parseElseBlock(.for_close) orelse {
                try self.emitError(
                    \\ Failed to parse For else block
                , .{});
                return null;
            };
            continue;
        }

        const statement = try self.parseStatement() orelse {
            try self.emitError(
                \\ Expected statement in for block
            , .{});
            return null;
        };

        try body.append(self.arena.allocator(), statement);
    }

    if (!self.expectPeekAndProgress(.for_close)) return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    return .{
        .access = access,
        .alternative = alternative,
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

fn parseIfStatement(self: *Self) Allocator.Error!?ast.IfStatement {
    if (!self.expectPeekAndProgress(.if_open)) return null;

    const condition = try self.parseExpressionStatement() orelse {
        try self.emitError("Expected to encounter an expression condition statement in if statement", .{});
        return null;
    };

    var body = ArrayList(ast.Statement).empty;
    var alternative: ?ast.ElseBlock = null;
    while (self.peek_token.typ != .if_close) {
        if (self.peek_token.typ == .@"else") {
            alternative = try self.parseElseBlock(.if_close) orelse {
                try self.emitError(
                    \\ Failed to parse If else block
                , .{});
                return null;
            };
            continue;
        }
        const statement = try self.parseStatement() orelse {
            try self.emitError(
                \\ Expected statement in if block
            , .{});
            return null;
        };

        // this may be wrong
        try body.append(self.arena.allocator(), statement);
    }

    if (!self.expectPeekAndProgress(.if_close)) return null;
    if (!self.expectPeekAndProgress(.statement_close)) return null;

    return .{
        .condition = condition,
        .alternative = alternative,
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

/// Expressions can appear between something following
/// `statement_open` & `statement_close` | `expression_open` & `expression_close`
fn parseExpressionStatement(self: *Self) Allocator.Error!?ast.ExpressionStatement {
    const first = blk: {
        switch (self.peek_token.typ) {
            .literal => {
                const literal_expr =
                    ast.LiteralExpression.tryFromStringLiteral(self.peek_token.literal) orelse {
                        try self.emitError(
                            \\ Failed to parse literal expression from string literal: '{s}'
                        , .{self.peek_token.literal});
                        return null;
                    };

                const expr =
                    try ast.ExpressionStatement.create(self.arena.allocator(), .{ .literal = literal_expr });

                std.debug.assert(self.expectPeekAndProgress(.literal));
                self.progressToken();
                break :blk expr;
            },
            .access => break :blk try ast.ExpressionStatement.create(
                self.arena.allocator(),
                .{ .access = try self.parseAccessExpression() orelse return null },
            ),
            else => {
                try self.emitError(
                    \\ Cannot parse expression statement starting with token: {any}
                , .{self.peek_token.typ});

                return null;
            },
        }
    };

    if (!self.current_token.typ.isComparison()) {
        switch (self.current_token.typ) {
            .expression_close, .statement_close => {
                self.progressToken();
            },
            else => |t| {
                try self.emitError(
                    \\ Expected expression statement to end with .expression_close or .statement_close
                    \\ Got: {any}
                , .{t});
                return null;
            },
        }
        return first;
    }

    const operator = ast.ComparisonExpression.Operator.tryFromTokenType(self.current_token.typ).?;
    const right = try self.parseExpressionStatement() orelse {
        try self.emitError("Failed to parse right side expression in comparison\n", .{});
        return null;
    };
    return try ast.ExpressionStatement.create(self.arena.allocator(), .{ .comparison = .{
        .operator = operator,
        .left = first,
        .right = right,
    } });
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
