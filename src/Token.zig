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

pub const keyword_map =
    std.StaticStringMap(Type).initComptime(.{
        .{ "||zz", .marker_open },
        .{ "zz||", .marker_close },
        .{ "{{", .expression_open },
        .{ "}}", .expression_close },
        .{ "for", .for_open },
        .{ "endfor", .for_close },
        .{ "in", .in },
        .{ "json", .json },
    });

const FirstLetterMapValue = struct {
    keyword: []const u8,
    node: std.SinglyLinkedList.Node,
};
const keys = blk: {
    var all: [keyword_map.kvs.len]struct {
        /// These keys are **ALWAYS** 1 len
        []const u8,
        FirstLetterMapValue,
    } = undefined;
    var all_len = 0;
    for (keyword_map.keys(), &all) |key, *k| {
        const val = FirstLetterMapValue{
            .keyword = key,
            .node = std.SinglyLinkedList.Node{},
        };
        const key_idx: ?usize = inner: {
            for (0..all_len) |i| {
                if (all[i].@"0"[0] == key[0]) break :inner i;
            }
            break :inner null;
        };
        if (key_idx) |i|
            all[i].@"1".node.next = val.node
        else {
            k.* = .{ &[_]u8{key[0]}, val };
            all_len += 1;
        }
    }

    break :blk all;
};

pub const first_char_map = std.StaticStringMap(FirstLetterMapValue).initComptime(keys);

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
    in,
    json,

    /// Some tokens are always the same literal
    // pub inline fn strLiteral(self: @This()) ?[]const u8 {
    //     return switch (self) {
    //         .space => " ",
    //         .newline => "\n",
    //         .marker_open => "||zz",
    //         .marker_close => "zz||",
    //         .expression_open => "{{",
    //         .expression_close => "}}",
    //         .for_open => "for",
    //         .for_close => "endfor",
    //         .in => "in",
    //         .json => "json",
    //         .literal, .access => null,
    //     };
    // }

    pub inline fn isWhitespace(self: @This()) bool {
        return switch (self) {
            .space, .newline => true,
            else => false,
        };
    }
};
