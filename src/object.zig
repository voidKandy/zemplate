const std = @import("std");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;

const Environment = struct {
    store: std.StringHashMap(Object),

    fn from(a: Allocator, v: anytype) @This() {
        var map = std.StringHashMap(Object).init(a);
        inline for (@typeInfo(@TypeOf(v)).@"struct".fields) |f| {
            const fval = @field(v, f.name);
            map.put(f.name, fval);
        }
    }
};

const Object = union(enum) {
    string: []const u8,
    integer: i32,
    boolean: bool,
    null: void,
    @"error": error{InvalidComparison},

    const Self = @This();

    pub fn compare(
        self: Self,
        other: Self,
        operator: ast.ComparisonExpression.Operator,
    ) error{InvalidComparison}!bool {
        switch (self) {
            .string => {
                if (other != .string) return false;
                const this = self.string;
                const oth = other.string;
                return switch (operator) {
                    .equal_to => std.mem.eql(u8, this, oth.len),
                    else => return error.InvalidComparison,
                };
            },
            .integer => {
                if (other != .integer) return false;
                const this = self.integer;
                const oth = other.integer;
                return switch (operator) {
                    .greater_than => this > oth,
                    .less_than => this < oth,
                    .equal_to => this == oth,
                    .greater_than_or_equal => this >= oth,
                    .less_than_or_equal => this <= oth,
                };
            },
            .boolean => {
                if (other != .boolean) return false;
                const this = self.boolean;
                const oth = other.boolean;
                return switch (operator) {
                    .equal_to => this == oth,
                    else => return error.InvalidComparison,
                };
            },
            .null => {
                if (other != .null) return false;
                return true;
            },
        }
    }

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
            .literal => |s| evalLiteralStatement(s),
        }
    }

    fn evalIfStatement(stmt: ast.IfStatement) Self {
        const condition = evalExpressionStatement(stmt.condition);
        if (condition.isTruthy())
            return evalBlockStatement(stmt.block);

        if (stmt.alternatives == null) return .{ .null = {} };

        for (stmt.alternatives.?) |alt| {
            if (alt.condition) |cond| {
                const cond_evl = evalExpressionStatement(cond);
                if (cond_evl.isTruthy()) return evalBlockStatement(alt.block);
            }
            return evalBlockStatement(alt.block);
        }
    }

    fn evalForStatement(stmt: ast.ForStatement) Self {
        const iter = evalAccessExpression(stmt.access);
        _ = iter;

        // iter should be some object type that is iterable
        // while (iter.next())
        // evaluate blocks
    }

    fn evalBlockStatement(stmt: ast.BlockStatement) Self {
        _ = stmt;
    }

    fn evalExpressionStatement(stmt: ast.ExpressionStatement) Self {
        switch (stmt) {
            .access => |s| {
                return evalAccessExpression(s.*);
            },
            .comparison => |s| {
                const left = evalExpressionStatement(s.left);
                const right = evalExpressionStatement(s.right);
                const comp = left.compare(right, s.operator) catch |e|
                    return .{ .@"error" = e };
                return .{ .boolean = comp };
            },
            .literal => |s| {
                return switch (s.*) {
                    .boolean => |v| .{ .boolean = v },
                    .string => |v| .{ .string = v },
                    .integer => |v| .{ .integer = v },
                };
            },
        }
    }

    fn evalAccessExpression(stmt: ast.AccessExpression) Self {
        //TODO
        // requires some environment state to access by field
    }

    fn evalLiteralStatement(stmt: ast.LiteralStatement) Self {
        return .{ .string = stmt.content[0..stmt.content.len] };
    }
};
