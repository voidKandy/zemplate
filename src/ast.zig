const std = @import("std");
const stdEql = std.mem.eql;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.ast);
const Token = @import("Token.zig");

pub const Program = struct {
    statements: std.ArrayList(Statement) = .empty,
};

pub const Statement = struct {
    variant: StatementVariant,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} statement:\n", .{@tagName(self.variant)});
        switch (self.variant) {
            .@"if" => |s| {
                try writer.print(
                    \\Condition:
                    \\ {f}
                , .{s.condition});

                if (s.body.len > 0) {
                    try writer.writeAll("If Body: \n");
                    for (s.body) |st| {
                        try writer.print(
                            \\ {f}
                            \\ 
                        , .{st});
                    }
                    try writer.writeAll("EndBody\n");
                }
                if (s.alternative) |alt| {
                    try writer.print("{f}\n", .{alt});
                }
            },
            .@"for" => |s| {
                try writer.print(
                    \\Access: {f}
                , .{s.access});

                if (s.body.len > 0) {
                    try writer.writeAll("For Body: \n");
                    for (s.body) |st| {
                        try writer.print(
                            \\ {f}
                            \\ 
                        , .{st});
                    }
                    try writer.writeAll("EndBody\n");
                }
                if (s.alternative) |alt| {
                    try writer.print("{f}\n", .{alt});
                }
            },
            .@"else" => |s| {
                try writer.print(
                    \\{f}
                , .{s});
            },
            .expression => |s| {
                try writer.print(
                    \\{f}
                , .{s});
            },
        }
    }

    pub fn eql(self: @This(), other: @This()) bool {
        switch (self.variant) {
            .@"if" => {
                if (other.variant != .@"if") return false;
                const this = self.variant.@"if";
                const oth = other.variant.@"if";

                if (!this.condition.eql(oth.condition) or this.body.len != oth.body.len) return false;
                for (this.body, oth.body) |th, ot| {
                    if (!th.eql(ot)) return false;
                }
                if (this.alternative) |th_alt| {
                    if (oth.alternative == null) return false;
                    if (oth.alternative.?.body.len != th_alt.body.len) return false;

                    for (th_alt.body, oth.alternative.?.body) |th, ot| {
                        if (!th.eql(ot)) return false;
                    }
                } else if (oth.alternative) |_| return false;
            },
            .@"for" => {
                if (other.variant != .@"for") return false;
                const this = self.variant.@"for";
                const oth = other.variant.@"for";
                if (!this.access.eql(oth.access) or this.body.len != oth.body.len) return false;

                for (this.body, oth.body) |th, ot| {
                    if (!th.eql(ot)) return false;
                }
                if (this.alternative) |th_alt| {
                    if (oth.alternative == null) return false;
                    if (oth.alternative.?.body.len != th_alt.body.len) return false;

                    for (th_alt.body, oth.alternative.?.body) |th, ot| {
                        if (!th.eql(ot)) return false;
                    }
                } else if (oth.alternative) |_| return false;
            },
            .@"else" => {
                if (other.variant != .@"else") return false;
                const this = self.variant.@"else";
                const oth = other.variant.@"else";
                if (this.body.len != oth.body.len) return false;

                for (this.body, oth.body) |th, ot| {
                    if (!th.eql(ot)) return false;
                }
            },
            .expression => {
                if (other.variant != .expression) return false;
                const this = self.variant.expression;
                const oth = other.variant.expression;
                return this.eql(oth);
            },
        }
        return true;
    }
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

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.body.len > 0) {
            try writer.writeAll("Else Body: \n");
            for (self.body) |st| {
                try writer.print(
                    \\ {f}
                    \\ 
                , .{st});
            }
        } else {
            try writer.writeAll("Else Body Empty\n");
        }
    }
};

pub const IfStatement = struct {
    condition: ExpressionStatement,
    body: []Statement,
    alternative: ?ElseStatement,
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
                try writer.print("Operator: {any}", .{exp.*.operator});
                try writer.print("Left: {f}", .{exp.*.left});
                try writer.print("Right: {f}", .{exp.*.right});
            },
            .literal => |exp| {
                try writer.print("{f}", .{exp.*});
            },
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
        try writer.print("{any} literal:", .{self});

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
