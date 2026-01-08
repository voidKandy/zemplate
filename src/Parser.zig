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
) ParseError!Self {
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

const ParseError = error{ OutOfMemory, WriteFailed, Unexpected };

pub fn logErrors(self: Self, _log: anytype) void {
    if (!@hasDecl(_log, "err") or
        !@hasDecl(_log, "warn") or
        !@hasDecl(_log, "info") or
        !@hasDecl(_log, "debug")) @panic("_log should be a type returned by std.log.scoped");

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

fn parseStatement(self: *Self) ParseError!?ast.Statement {
    self.skipCurrentWhitespace();
    switch (self.current_token.typ) {
        .statement_open => {
            self.progressTokenSkipWhitespace();
            return self.parseStatement();
        },
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

        .expression_open => return .{ .expression = try self.parseExpressionStatement() orelse {
            try self.emitError(
                \\ Failed to parse expression statement
                \\ Parser state:
                \\ {f}
            , .{self});
            return null;
        } },
        .literal => return .{ .literal = try self.parseLiteralStatement() orelse {
            try self.emitError(
                \\ Failed to parse literal statement
                \\ Parser state:
                \\ {f}
            , .{self});
            return null;
        } },
        else => {},
    }

    try self.emitError(
        \\ Could not parse statement that begins with token: {f}  
    , .{self.current_token});
    return null;
}

fn parseLiteralStatement(self: *Self) ParseError!?ast.LiteralStatement {
    var writer: std.Io.Writer.Allocating = .init(self.arena.allocator());
    if (!try self.expectCurrent(.literal)) return null;

    if (self.prev_token) |p| {
        if (p.typ.isWhitespace()) {
            try writer.writer.writeAll(p.literal);
        }
    }

    defer writer.deinit();
    while (true) {
        try writer.writer.writeAll(self.current_token.literal);
        if (!self.peek_token.typ.isWhitespace() and self.peek_token.typ != .literal) break;
        self.progressToken();
    }

    return ast.LiteralStatement{
        .content = try writer.toOwnedSlice(),
    };
}

fn parseAccessExpression(self: *Self) ParseError!?ast.AccessExpression {
    if (!try self.expectCurrent(.access)) return null;
    var access = ast.AccessExpression{
        .literal = self.current_token.literal,
    };
    self.progressTokenSkipWhitespace();

    while (self.current_token.typ != .expression_close and
        self.current_token.typ != .statement_close and
        !self.current_token.typ.isComparison())
    {
        // when more serialization options are added
        // this will need to account for those
        switch (self.current_token.typ) {
            .json => access.json = true,
            else => log.warn(
                \\ Token ignored when parsing access token: {f}
            , .{self.peek_token}),
        }
        self.progressTokenSkipWhitespace();
    }

    return access;
}

fn parseElseBlock(self: *Self, if_or_for: enum { @"if", @"for" }) ParseError!?ast.ElseBlock {
    if (!try self.expectCurrent(.@"else")) return null;
    self.progressTokenSkipWhitespace();

    var condition: ?ast.ExpressionStatement = null;
    if (self.current_token.typ == .if_open)
        condition = try self.parseExpressionStatement() orelse {
            try self.emitError(
                \\ Else statement contained 'if' but no condition followed
            , .{});
            return null;
        };

    if (!try self.expectCurrent(.statement_close)) return null;
    self.progressTokenSkipWhitespace();

    var body = ArrayList(ast.Statement).empty;
    var nesting_depth: usize = 0;
    const opening_tag: Token.Type, const closing_tag: Token.Type =
        switch (if_or_for) {
            .@"for" => .{ .for_open, .for_close },
            .@"if" => .{ .if_open, .if_close },
        };

    while (true) {
        if (self.current_token.typ == .statement_open) self.progressTokenSkipWhitespace();
        if (self.current_token.typ == .@"else") break;
        if (self.current_token.typ == closing_tag) {
            if (nesting_depth == 0) break else nesting_depth -= 1;
        }
        if (self.current_token.typ == opening_tag) nesting_depth += 1;

        const statement = try self.parseStatement() orelse {
            try self.emitError(
                \\ Expected statement in block
            , .{});
            return null;
        };
        try body.append(self.arena.allocator(), statement);
        self.progressTokenSkipWhitespace();
    }

    if (self.current_token.typ != closing_tag and self.current_token.typ != .@"else")
        try self.emitError(
            \\ Expected Else Statement to end with {any} or {any}
            \\ Instead got: {any}
        , .{ closing_tag, .@"else", self.current_token.typ });

    // if (!try self.expectCurrent(closing_tag)) return null;

    return .{
        .condition = condition,
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

fn parseForStatement(self: *Self) ParseError!?ast.ForStatement {
    if (!try self.expectCurrent(.for_open)) return null;

    self.progressTokenSkipWhitespace();
    const access = try self.parseAccessExpression() orelse {
        try self.emitError("Expected to encounter an access expression statement in for statement", .{});
        return null;
    };

    var body: ArrayList(ast.Statement) = .empty;
    var alternatives: ArrayList(ast.ElseBlock) = .empty;

    self.progressTokenSkipWhitespace();
    if (self.current_token.typ == .statement_open) self.progressTokenSkipWhitespace();
    while (true) {
        switch (self.current_token.typ) {
            .for_close => break,
            .@"else" => {
                const else_blk = try self.parseElseBlock(.@"for") orelse {
                    try self.emitError(
                        \\ Failed to parse For else block
                    , .{});
                    return null;
                };
                try alternatives.append(self.arena.allocator(), else_blk);
                continue;
            },
            else => {
                const statement = try self.parseStatement() orelse {
                    try self.emitError(
                        \\ Expected statement in for block
                    , .{});
                    return null;
                };

                if (self.current_token.typ == .statement_close) self.progressToken();

                try body.append(self.arena.allocator(), statement);
                self.progressTokenSkipWhitespace();
                if (self.current_token.typ == .statement_open) self.progressTokenSkipWhitespace();
            },
        }
    }

    if (!try self.expectCurrent(.for_close)) return null;
    self.progressTokenSkipWhitespace();
    if (!try self.expectCurrent(.statement_close)) return null;
    return .{
        .access = access,
        .alternatives = if (alternatives.items.len == 0) null else try alternatives.toOwnedSlice(self.arena.allocator()),
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

fn parseIfStatement(self: *Self) ParseError!?ast.IfStatement {
    if (!try self.expectCurrent(.if_open)) return null;

    const condition = try self.parseExpressionStatement() orelse {
        try self.emitError("Expected to encounter an conditional expression statement in if statement", .{});
        return null;
    };

    var body: ArrayList(ast.Statement) = .empty;
    var alternatives: ArrayList(ast.ElseBlock) = .empty;

    self.progressTokenSkipWhitespace();
    if (self.current_token.typ == .statement_open) self.progressTokenSkipWhitespace();
    while (true) {
        switch (self.current_token.typ) {
            .if_close => break,
            .@"else" => {
                const else_blk = try self.parseElseBlock(.@"if") orelse {
                    try self.emitError(
                        \\ Failed to parse If else block
                    , .{});
                    return null;
                };
                try alternatives.append(self.arena.allocator(), else_blk);
                continue;
            },
            else => {
                const statement = try self.parseStatement() orelse {
                    try self.emitError(
                        \\ Expected statement in if block
                    , .{});
                    return null;
                };
                if (self.current_token.typ == .statement_close) self.progressToken();

                try body.append(self.arena.allocator(), statement);
                self.progressTokenSkipWhitespace();
                if (self.current_token.typ == .statement_open) self.progressTokenSkipWhitespace();
            },
        }
    }

    if (!try self.expectCurrent(.if_close)) return null;
    self.progressTokenSkipWhitespace();
    if (!try self.expectCurrent(.statement_close)) return null;

    return .{
        .condition = condition,
        .alternatives = if (alternatives.items.len == 0) null else try alternatives.toOwnedSlice(self.arena.allocator()),
        .block = .{
            .body = try body.toOwnedSlice(self.arena.allocator()),
        },
    };
}

/// Expressions can appear between something following
/// `statement_open` & `statement_close` | `expression_open` & `expression_close`
fn parseExpressionStatement(self: *Self) ParseError!?ast.ExpressionStatement {
    self.progressTokenSkipWhitespace();

    const first = blk: {
        switch (self.current_token.typ) {
            .literal => {
                const literal_expr =
                    ast.LiteralExpression.tryFromStringLiteral(self.current_token.literal) orelse {
                        try self.emitError(
                            \\ Failed to parse literal expression from string literal: '{s}'
                        , .{self.peek_token.literal});
                        return null;
                    };

                const expr = try ast.ExpressionStatement.create(self.arena.allocator(), .{ .literal = literal_expr });

                self.progressTokenSkipWhitespace();
                break :blk expr;
            },
            .access => break :blk try ast.ExpressionStatement.create(
                self.arena.allocator(),
                .{ .access = try self.parseAccessExpression() orelse return null },
            ),
            else => {
                try self.emitError(
                    \\ Cannot parse expression statement starting with token: {any}
                , .{self.current_token.typ});

                return null;
            },
        }
    };

    // self.progressTokenSkipWhitespace();
    if (!self.current_token.typ.isComparison()) {
        switch (self.current_token.typ) {
            .expression_close, .statement_close => {},
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

fn progressToken(self: *Self) void {
    self.prev_token = self.current_token;
    self.current_token = self.peek_token;
    self.peek_token = self.lexer.nextToken();
}

/// consumes tokens until current_token is not whitespace
fn skipCurrentWhitespace(self: *Self) void {
    while (self.current_token.typ.isWhitespace()) {
        self.progressToken();
    }

    std.debug.assert(!self.current_token.typ.isWhitespace());
}

/// Progresses tokens, ensuring current != whitespace
fn progressTokenSkipWhitespace(self: *Self) void {
    self.progressToken();
    self.skipCurrentWhitespace();
}

fn expectCurrent(self: *Self, expected_current: Token.Type) Allocator.Error!bool {
    if (self.current_token.typ == expected_current) {
        return true;
    }

    try self.emitError(
        \\ Expected current to be {any}, got {f} instead
    , .{ expected_current, self.current_token });
    return false;
}

fn expectPrevious(self: *Self, expected_prev: Token.Type) Allocator.Error!bool {
    if (self.prev_token != null and self.prev_token.?.typ == expected_prev) {
        return true;
    }
    try self.emitError(
        \\ Expected previous to be {any}, got {s} instead
    , .{ expected_prev, if (self.prev_token) |p| @tagName(p.typ) else "null" });
    return false;
}

fn expectPeekAndProgress(self: *Self, expected_next: Token.Type) Allocator.Error!bool {
    if (self.peek_token.typ == expected_next) {
        self.progressToken();
        return true;
    }

    try self.emitError(
        \\ Expected next token to be {any}, got {f} instead
    , .{ expected_next, self.peek_token });
    return false;
}

fn emitError(self: *Self, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    try self.errors.append(
        self.arena.allocator(),
        try allocPrint(self.arena.allocator(), fmt, args),
    );
}
