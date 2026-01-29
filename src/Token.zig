const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.Token);

literal: []const u8,
type: Type,

const Self = @This();

pub fn create(str: []const u8, typ: Type) Self {
    return .{ .literal = str, .type = typ };
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return try writer.print(
        \\[.{s}: '{s}']
    , .{ @tagName(self.type), self.literal });
}

pub inline fn eql(self: Self, other: Self) bool {
    return (mem.eql(u8, self.literal, other.literal) and
        @intFromEnum(self.type) == @intFromEnum(other.type));
}

pub const EOF = Self{
    .literal = "",
    .type = .eof,
};

pub const Type = enum {
    space,
    tab,
    newline,
    string_wrapper,
    literal,
    access,
    statement_open,
    statement_close,
    expression_open,
    expression_close,
    for_open,
    for_close,
    if_open,
    if_close,
    @"else",
    greater_than,
    less_than,
    equal_to,
    greater_than_or_equal,
    less_than_or_equal,
    json,
    eof,

    pub fn eql(self: @This(), other: @This()) bool {
        return @intFromEnum(self) == @intFromEnum(other);
    }
    pub inline fn isWhitespace(self: @This()) bool {
        return switch (self) {
            .space, .newline, .tab => true,
            else => false,
        };
    }
    pub inline fn isComparison(self: @This()) bool {
        return switch (self) {
            .greater_than,
            .less_than,
            .equal_to,
            .greater_than_or_equal,
            .less_than_or_equal,
            => true,
            else => false,
        };
    }
};

pub const keyword_map = std.StaticStringMap(Type).initComptime(.{
    .{ "||zz", .statement_open },
    .{ "zz||", .statement_close },
    .{ "{|", .expression_open },
    .{ "|}", .expression_close },
    .{ "for", .for_open },
    .{ "endfor", .for_close },
    .{ "if", .if_open },
    .{ "else", .@"else" },
    .{ "endif", .if_close },
    .{ "json", .json },
    .{ ">", .greater_than },
    .{ "<", .less_than },
    .{ "==", .equal_to },
    .{ ">=", .greater_than_or_equal },
    .{ "<=", .less_than_or_equal },
});

/// MUST be initialized
/// Best done by lexer
pub const FirstCharMap = struct {
    var singleton: std.AutoHashMap(u8, [][]const u8) = undefined;
    var initialized: bool = false;

    pub fn get() *const std.AutoHashMap(u8, [][]const u8) {
        if (initialized)
            return &singleton;
        @panic("tried to access uninitialized FirstCharMap");
    }

    pub fn init() std.mem.Allocator.Error!void {
        const a = std.heap.page_allocator;
        var map = std.AutoHashMap(u8, std.ArrayList([]const u8)).init(a);
        defer map.deinit();

        for (keyword_map.keys()) |key| {
            const ch = key[0];
            if (map.getPtr(ch)) |arr| {
                try arr.append(a, key);
            } else {
                var arr = try std.ArrayList([]const u8).initCapacity(a, 8);
                try arr.append(a, key);
                try map.put(ch, arr);
            }
        }
        var result = std.AutoHashMap(u8, [][]const u8).init(a);

        var iter = map.iterator();
        while (iter.next()) |entry| {
            try result.put(entry.key_ptr.*, try entry.value_ptr.*.toOwnedSlice(a));
        }

        singleton = result;
        initialized = true;
    }

    pub fn deinit() void {
        singleton.deinit();
    }
};
