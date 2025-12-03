const std = @import("std");
const log = std.log.scoped(.Lexer);
const mem = std.mem;
const ArrayList = std.ArrayList;
const Token = @import("Token.zig");

input: []const u8,
pos: usize,
/// keeps track of the last NON WHITESPACE token
prev_token: ?Token.Type = null,
/// Marks if we are currently between marker_open and marker_close
between_markers: bool = false,

const Self = @This();

pub fn init(input: []const u8) Self {
    const l = Self{
        .input = input,
        .pos = 0,
    };

    // for (0..Token.first_char_map.kvs.len) |i| {
    //     const value = Token.first_char_map.kvs.values[i];
    //     const key = Token.first_char_map.kvs.keys[i];
    //     log.warn(
    //         \\ KEY: {s}
    //         \\ VAL: {any}
    //     , .{ key, value });
    // }
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

/// Reads characters until a whitespace is encountered
/// returns the amount of characters read
fn readWord(self: *Self) usize {
    const start_pos = self.pos;
    while (self.peekNext()) |ch| {
        log.warn("next char: {c}", .{ch.*});
        const encountered_keyword = blk: {
            if (Token.first_char_map.get(&[_]u8{ch.*})) |val| {
                const window_start = self.pos;
                const window_end = window_start + val.keyword.len;
                log.warn(
                    \\ Checking equality of: {s}
                    \\ and
                    \\ {s}
                , .{ self.input[window_start..window_end], val.keyword });
                break :blk std.mem.eql(u8, self.input[window_start..window_end], val.keyword);
            }
            break :blk false;
        };

        if (!std.ascii.isWhitespace(ch.*) and !encountered_keyword)
            _ = self.progress().?
        else
            break;
    }
    return self.pos - start_pos;
}

pub fn nextToken(self: *Self, a: mem.Allocator) mem.Allocator.Error!?Token {
    var slice_end: usize = self.pos + 1;
    var slice_start: usize = self.pos;
    var current_byte: ?u8 = null;

    const token_opt: ?Token = outer: while (self.progress()) |c| : (slice_end += 1) {
        switch (c) {
            ' ' => break :outer Token.create(" ", .space),
            '\n' => break :outer Token.create("\n", .newline),
            else => {},
        }
        log.debug("char: {c}\npos: {d}\nstart: {d}\nend: {d}\n", .{ c, self.pos, slice_start, slice_end });

        const possible_match: ?struct { []const u8, Token.Type } = blk: {
            for (Token.keyword_map.keys()) |key| {
                if (c == key[0]) break :blk .{ key, Token.keyword_map.get(key).? };
            }
            break :blk null;
        };

        if (possible_match) |tup| {
            if (tup.@"1" == .json)
                if (self.prev_token orelse continue :outer != .access)
                    continue :outer;
            if (tup.@"1" == .for_open or tup.@"1" == .for_close)
                if (self.prev_token orelse continue :outer != .marker_open)
                    continue :outer;

            // const str = tok.literal().?;

            for (1..tup.@"0".len) |i| {
                if (!b: {
                    const next = self.peekNext() orelse break :b false;
                    break :b next.* == tup.@"0"[i];
                }) continue :outer;

                current_byte = self.progress();
                slice_end += 1;
            }
            // if (mem.eql(u8, self.input[slice_start..slice_end], tup.literal().?))
            break :outer Token.create(self.input[slice_start..slice_end], tup.@"1");
        }

        const tok: Token.Type = blk: {
            // access tokens are always between markers and always start with a '.'
            // might be after an expression_open {{ or between markers
            if (self.prev_token) |prev| {
                switch (prev) {
                    .expression_open => if (self.input[slice_start..slice_end][0] == '.') break :blk .access,
                    else => {},
                }
            }
            if (self.between_markers and self.input[slice_start..slice_end][0] == '.') break :blk .access;
            break :blk .literal;
        };

        if (self.peekNext() != null)
            slice_end += self.readWord();
        break :outer Token.create(self.input[slice_start..slice_end], tok);
    } else {
        break :outer null;
    };
    slice_start = self.pos;

    if (token_opt) |token| {
        const debug_str = try token.debugStr(a);
        defer a.free(debug_str);
        if (!token.typ.isWhitespace())
            self.prev_token = token.typ;

        if (token.typ == .marker_open)
            self.between_markers = true;
        if (token.typ == .marker_close) {
            std.debug.assert(self.between_markers);
            self.between_markers = false;
        }

        log.debug("Got Token:\n{s}", .{debug_str});
    }
    return token_opt;
}
