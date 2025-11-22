const std = @import("std");
const log = std.log.scoped(.Lexer);
const mem = std.mem;
const ArrayList = std.ArrayList;
const Token = @import("Token.zig");

input: []const u8,
pos: usize,
// keeps track of the last NON WHITESPACE token
prev_token: ?Token.Type = null,

const Self = @This();

pub fn init(input: []const u8) Self {
    const l = Self{
        .input = input,
        .pos = 0,
    };
    return l;
}

pub fn debugStr(self: Self, a: mem.Allocator) mem.Allocator.Error![]u8 {
    std.fmt.allocPrint(a,
        \\ lexer:
        \\ position: {d}
        \\ next_position: {d}
        \\ char: {c}
        \\ input: {s}
    , .{ self.pos, self.next_pos, self.ch, self.input });
}

/// Move forward by one byte
/// returns current char
pub fn progress(self: *Self) ?u8 {
    if (self.pos >= self.input.len) {
        return null;
    }
    const ret = self.input[self.pos];
    self.pos += 1;
    return ret;
}

/// returns an optional pointer to the next char
pub fn peekNext(self: *Self) ?*const u8 {
    if (self.pos >= self.input.len) {
        return null;
    }
    return &self.input[self.pos];
}

pub fn nextToken(self: *Self, a: mem.Allocator) mem.Allocator.Error!?Token {
    var slice_end: usize = self.pos + 1;
    var slice_start: usize = self.pos;
    var current_byte: ?u8 = null;

    const token_opt: ?Token = outer: while (self.progress()) |c| : (slice_end += 1) {
        log.debug("char: {c}\npos: {d}\nstart: {d}\nend: {d}\n", .{ c, self.pos, slice_start, slice_end });
        const possible_match: ?Token.Type =
            switch (c) {
                Token.Type.marker_close.literal().?[0] => .marker_close,
                Token.Type.marker_open.literal().?[0] => .marker_open,
                Token.Type.json.literal().?[0] => .json,
                Token.Type.newline.literal().?[0] => break :outer Token.create(self.input[slice_start..slice_end], .newline),
                Token.Type.space.literal().?[0] => break :outer Token.create(self.input[slice_start..slice_end], .space),

                else => null,
            };

        if (possible_match) |tok| {
            const str = tok.literal().?;

            for (1..str.len) |i| {
                if (!b: {
                    const next = self.peekNext() orelse break :b false;
                    break :b next.* == str[i];
                }) continue :outer;

                current_byte = self.progress();
                slice_end += 1;
            }
            if (mem.eql(u8, self.input[slice_start..slice_end], tok.literal().?))
                break :outer Token.create(self.input[slice_start..slice_end], tok);
        }

        const tok: Token.Type = blk: {
            if (self.prev_token) |prev| {
                switch (prev) {
                    // access tokens are always after marker_open and always start with a '.'
                    .marker_open => if (self.input[slice_start..slice_end][0] == '.') break :blk .access,
                    else => {},
                }
            }
            break :blk .generic;
        };

        if (self.peekNext() == null or
            self.peekNext().?.* == Token.Type.space.literal().?[0] or
            self.peekNext().?.* == Token.Type.newline.literal().?[0] or
            self.peekNext().?.* == Token.Type.json.literal().?[0] or
            self.peekNext().?.* == Token.Type.marker_open.literal().?[0] or
            self.peekNext().?.* == Token.Type.marker_close.literal().?[0])
            break :outer Token.create(self.input[slice_start..slice_end], tok);
    } else {
        break :outer null;
    };
    slice_start = self.pos;

    if (token_opt) |token| {
        const debug_str = try token.debugStr(a);
        defer a.free(debug_str);
        if (!token.typ.isWhitespace()) {
            self.prev_token = token.typ;
        }
        log.debug("Got Token:\n{s}", .{debug_str});
    }
    return token_opt;
}
