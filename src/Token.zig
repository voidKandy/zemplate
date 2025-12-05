const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.Token);

literal: []const u8,
typ: Type,

const Self = @This();

pub fn create(str: []const u8, typ: Type) Self {
    return .{ .literal = str, .typ = typ };
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return try writer.print(
        \\
        \\ --- .{s} ---
        \\ Literal: [{s}]
        \\
    , .{ @tagName(self.typ), self.literal });
}

pub inline fn eql(self: Self, other: Self) bool {
    return (mem.eql(u8, self.literal, other.literal) and
        @intFromEnum(self.typ) == @intFromEnum(other.typ));
}

pub const Type = enum {
    space,
    newline,
    literal,
    access,
    marker_open,
    marker_close,
    expression_open,
    expression_close,
    for_open,
    for_close,
    json,

    pub inline fn isWhitespace(self: @This()) bool {
        return switch (self) {
            .space, .newline => true,
            else => false,
        };
    }
};

pub const keyword_map = std.StaticStringMap(Type).initComptime(.{
    .{ "||zz", .marker_open },
    .{ "zz||", .marker_close },
    .{ "{{", .expression_open },
    .{ "}}", .expression_close },
    .{ "for", .for_open },
    .{ "endfor", .for_close },
    .{ "json", .json },
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
