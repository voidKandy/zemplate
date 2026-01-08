const std = @import("std");
const stdEql = std.mem.eql;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.ast);
const Token = @import("Token.zig");

pub const Program = struct {
    statements: std.ArrayList(Statement) = .empty,
};

pub const Statement = union(enum) {
    block: BlockStatement,
    @"for": ForStatement,
    @"if": IfStatement,
    expression: ExpressionStatement,
    literal: LiteralStatement,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} statement:\n", .{@tagName(self)});
        try switch (self) {
            .@"if" => |s| s.format(writer),
            .@"for" => |s| s.format(writer),
            .block => |s| s.format(writer),
            .expression => |s| s.format(writer),
            .literal => |s| s.format(writer),
        };
    }

    pub fn eql(self: @This(), other: @This()) bool {
        switch (self) {
            .@"if" => {
                if (other != .@"if") return false;
                const this = self.@"if";
                const oth = other.@"if";
                return this.eql(oth);
            },
            .@"for" => {
                if (other != .@"for") return false;
                const this = self.@"for";
                const oth = other.@"for";
                return this.eql(oth);
            },
            .block => {
                if (other != .block) return false;
                const this = self.block;
                const oth = other.block;
                return this.eql(oth);
            },
            .expression => {
                if (other != .expression) return false;
                const this = self.expression;
                const oth = other.expression;
                return this.eql(oth);
            },
            .literal => {
                if (other != .literal) return false;
                const this = self.literal;
                const oth = other.literal;
                return this.eql(oth);
            },
        }
        return true;
    }
};

pub const LiteralStatement = struct {
    content: []u8,

    pub fn eql(self: @This(), other: @This()) bool {
        return std.mem.eql(u8, self.content, other.content);
    }
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ Literal Statement:
            \\ '{s}'
        , .{self.content});
    }
};

pub const ElseBlock = struct {
    condition: ?ExpressionStatement,
    block: BlockStatement,
    pub fn eql(self: @This(), other: @This()) bool {
        if (self.condition) |c| {
            if (other.condition == null) return false;
            if (!c.eql(other.condition.?)) return false;
        } else if (other.condition != null) return false;
        return self.block.eql(other.block);
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.condition) |cond| {
            try writer.writeAll(
                \\ Condition:
                \\
            );
            try cond.format(writer);
        }
        try self.block.format(writer);
    }
};

pub const ForStatement = struct {
    access: AccessExpression,
    block: BlockStatement,
    alternatives: ?[]ElseBlock,

    pub fn eql(self: @This(), other: @This()) bool {
        if (!self.access.eql(other.access) or
            !self.block.eql(other.block)) return false;

        if (self.alternatives) |th_alt| {
            if (other.alternatives == null or other.alternatives.?.len != th_alt.len) return false;
            for (th_alt, other.alternatives.?) |th, o| if (!th.eql(o)) return false;
        } else if (other.alternatives) |_| return false;
        return true;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\Access: {f}
        , .{self.access});

        if (self.block.body.len > 0) {
            try writer.writeAll("For Body: \n");
            try self.block.format(writer);
            try writer.writeAll("End For Body\n");
        }
        if (self.alternatives) |alts| for (alts) |alt| try alt.format(writer);
    }
};

pub const BlockStatement = struct {
    body: []Statement,

    pub fn eql(self: @This(), other: @This()) bool {
        if (self.body.len != other.body.len) return false;
        for (self.body, other.body) |th, ot| {
            if (!th.eql(ot)) return false;
        }
        return true;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.body.len > 0) {
            try writer.writeAll("{\n");
            for (self.body) |st| {
                try st.format(writer);
            }
            try writer.writeAll("}\n");
        } else {
            try writer.writeAll("Block Empty\n");
        }
    }
};

pub const IfStatement = struct {
    condition: ExpressionStatement,
    block: BlockStatement,
    alternatives: ?[]ElseBlock,

    pub fn eql(self: @This(), other: @This()) bool {
        if (!self.condition.eql(other.condition) or
            !self.block.eql(other.block)) return false;

        if (self.alternatives) |th_alt| {
            if (other.alternatives == null or other.alternatives.?.len != th_alt.len) return false;
            for (th_alt, other.alternatives.?) |th, o| if (!th.eql(o)) return false;
        } else if (other.alternatives) |_| return false;
        return true;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\Condition:
            \\ {f}
        , .{self.condition});

        if (self.block.body.len > 0) {
            try writer.writeAll("If Body: \n");
            try self.block.format(writer);
            try writer.writeAll("End If Body\n");
        }
        if (self.alternatives) |alts| for (alts) |alt| try alt.format(writer);
    }
};

pub const ExpressionStatement = union(enum) {
    access: *AccessExpression,
    comparison: *ComparisonExpression,
    literal: *LiteralExpression,

    pub fn eql(self: @This(), other: @This()) bool {
        switch (self) {
            .access => {
                if (other != .access) return false;
                const this = self.access.*;
                const oth = other.access.*;
                if (this.json != oth.json or !stdEql(u8, this.literal, oth.literal)) return false;
            },
            .comparison => {
                if (other != .comparison) return false;
                const this = self.comparison.*;
                const oth = other.comparison.*;
                if (@intFromEnum(this.operator) != @intFromEnum(oth.operator) or !this.left.eql(oth.left) or !this.right.eql(oth.right)) return false;
            },
            .literal => {
                if (other != .literal) return false;
                const this = self.literal.*;
                const oth = other.literal.*;
                if (!this.eql(oth)) return false;
            },
        }
        return true;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} expression:\n", .{@tagName(self)});

        switch (self) {
            .access => |exp| {
                try writer.print("{f}", .{exp.*});
            },
            .comparison => |exp| {
                try writer.print(
                    \\Operator: {any}
                    \\
                , .{exp.*.operator});
                try writer.print(
                    \\Left: {f}
                    \\
                , .{exp.*.left});
                try writer.print(
                    \\Right: {f}
                    \\
                , .{exp.*.right});
            },
            .literal => |exp| {
                try writer.print("{f}", .{exp.*});
            },
        }
    }

    pub fn destroy(self: @This(), a: Allocator) void {
        switch (self) {
            .access => |val| a.destroy(val),
            .comparison => |val| a.destroy(val),
            .literal => |val| a.destroy(val),
        }
    }

    pub fn create(a: Allocator, expr: union(enum) {
        access: AccessExpression,
        comparison: ComparisonExpression,
        literal: LiteralExpression,
    }) Allocator.Error!@This() {
        switch (expr) {
            .access => |ac| {
                const ptr = try a.create(AccessExpression);
                ptr.* = ac;
                return .{
                    .access = ptr,
                };
            },
            .comparison => |c| {
                const ptr = try a.create(ComparisonExpression);
                ptr.* = c;
                return .{
                    .comparison = ptr,
                };
            },
            .literal => |l| {
                const ptr = try a.create(LiteralExpression);
                ptr.* = l;
                return .{
                    .literal = ptr,
                };
            },
        }
    }
};

pub const AccessExpression = struct {
    literal: []const u8,
    /// this will need to be changed if more serialization options are ever needed
    json: bool = false,

    pub fn eql(self: @This(), other: @This()) bool {
        return (stdEql(u8, self.literal, other.literal) and self.json == other.json);
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ Literal: {s}
            \\ JSON: {any}
            \\
        , .{ self.literal, self.json });
    }
};

pub const ComparisonExpression = struct {
    operator: Operator,
    left: ExpressionStatement,
    right: ExpressionStatement,

    pub const Operator = enum {
        greater_than,
        less_than,
        equal_to,
        greater_than_or_equal,
        less_than_or_equal,

        pub fn tryFromTokenType(typ: Token.Type) ?@This() {
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

pub const LiteralExpression = union(enum) {
    integer: u32,
    string: []const u8,
    boolean: bool,

    pub fn eql(self: @This(), other: @This()) bool {
        switch (self) {
            .integer => {
                if (other != .integer) return false;
                if (self.integer != other.integer) return false;
            },
            .string => {
                if (other != .string) return false;
                if (!stdEql(u8, self.string, other.string)) return false;
            },
            .boolean => {
                if (other != .boolean) return false;
                if (self.boolean != other.boolean) return false;
            },
        }
        return true;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} literal: ", .{@tagName(self)});

        switch (self) {
            .integer => |int| {
                try writer.print("{d}", .{int});
            },
            .string => |str| {
                try writer.print("'{s}'", .{str});
            },
            .boolean => |b| {
                try writer.print("{any}", .{b});
            },
        }
        try writer.writeByte('\n');
    }

    pub fn tryFromStringLiteral(literal: []const u8) ?@This() {
        const int = std.fmt.parseInt(u32, literal, 10) catch |e| {
            if (e == error.Overflow) @panic("Overflow when parsing integer!");

            if (std.mem.eql(u8, "false", literal) or std.mem.eql(u8, "true", literal)) {
                return .{ .boolean = std.mem.eql(u8, "true", literal) };
            }

            if (literal[0] == '\'' and literal[literal.len - 1] == '\'') {
                return .{ .string = literal[1 .. literal.len - 1] };
            }

            return null;
        };

        return .{ .integer = int };
    }
};
