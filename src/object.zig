const std = @import("std");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;

const Object = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
    null: void,

    const Self = @This();

    pub fn isTruthy(self: Self) bool {
        switch (self) {
            .boolean => |b| return b,
            else => return false,
        }
    }

    pub fn eval(statement: ast.Statement) Self {
        switch (statement) {
            .@"if" => |s| evalIfStatement(s),
            .@"for" => |s| evalForStatement(s),
            .block => |s| evalBlockStatement(s),
            .expression => |s| evalExpressionStatement(s),
        }
    }

    fn evalIfStatement(stmt: ast.IfStatement) Self {
        const condition = evalExpressionStatement(stmt.condition);
        if (condition.isTruthy()) {}
    }

    fn evalForStatement(stmt: ast.ForStatement) Self {}

    fn evalBlockStatement(stmt: ast.BlockStatement) Self {}

    fn evalExpressionStatement(stmt: ast.ExpressionStatement) Self {}
};
