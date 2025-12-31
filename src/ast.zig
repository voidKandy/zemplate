const std = @import("std");
const log = std.log.scoped(.ast);
const Token = @import("Token.zig");

pub const Program = struct {
    statements: std.ArrayList(Statement) = .empty,
};

pub const Statement = struct {
    // token: Token,
    variant: StatementVariant,
};

pub const StatementVariant = union(enum) {
    @"for": ForStatement,
    @"if": IfStatement,
    @"else": ElseStatement,
    expression: ExpressionStatement,
};

pub const ForStatement = struct {
    access: AccessExpression,
    body: []Statement,
    alternative: ?ElseStatement,
};

pub const ElseStatement = struct {
    body: []Statement,
};

pub const IfStatement = struct {
    condition: ExpressionStatement,
    body: []Statement,
    alternative: ?ElseStatement,
};

pub const ExpressionStatement = union(enum) {
    access: AccessExpression,
    comparison: ComparisonExpression,
    literal: LiteralExpression,
};

const AccessExpression = struct {
    literal: []const u8,
    /// this will need to be changed if more serialization options are ever needed
    json: bool = false,
};

const ComparisonExpression = struct {
    operator: Operator,
    left: ExpressionStatement,
    right: ExpressionStatement,

    const Operator = enum {
        greater_than,
        less_than,
        equal_to,
        greater_than_or_equal,
        less_than_or_equal,

        fn tryFromTokenType(typ: Token.Type) @This() {
            return switch (typ) {
                .greater_than => .greater_than,
                .less_than => .less_than,
                .equal_to => .equal_to,
                .greater_than_or_equal => .greater_than_or_equal,
                .less_than_or_equal => .less_than_or_equal,
                else => null,
            };
        }
    };
};

const LiteralExpression = union(enum) {
    integer: u32,
    string: []const u8,
    boolean: bool,
};
