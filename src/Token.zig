const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.Token);

literal: []const u8,
typ: Type,

const Self = @This();

pub fn create(str: []const u8, typ: Type) Self {
    return .{ .literal = str, .typ = typ };
}

pub inline fn debugStr(self: Self, a: mem.Allocator) mem.Allocator.Error![]u8 {
    return try std.fmt.allocPrint(a,
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
    marker_open,
    marker_close,
    json,
    generic,
    access,

    /// Some tokens are always the same literal
    pub inline fn literal(self: @This()) ?[]const u8 {
        return switch (self) {
            .space => " ",
            .newline => "\n",
            .marker_open => "||zz",
            .marker_close => "zz||",
            .json => "json",
            .generic, .access => null,
        };
    }

    pub inline fn isWhitespace(self: @This()) bool {
        return switch (self) {
            .space, .newline => true,
            else => false,
        };
    }
};
