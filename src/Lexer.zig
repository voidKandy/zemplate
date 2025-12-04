const std = @import("std");
const log = std.log.scoped(.Lexer);
const mem = std.mem;
const ArrayList = std.ArrayList;
const Token = @import("Token.zig");
const Error = @import("root.zig").Error;

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

    Token.FirstCharMap.init() catch @panic("failed to initialize first char map");

    var iter = Token.FirstCharMap.get().iterator();
    while (iter.next()) |e| {
        log.info(
            \\ {c}:
        , .{
            e.key_ptr.*,
        });
        for (e.value_ptr.*) |v| {
            log.info(
                \\ {s} 
            , .{
                v,
            });
        }
    }

    return l;
}

pub fn deinit(_: Self) void {
    Token.FirstCharMap.deinit();
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
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

/// returns an optional pointer to the next nth char
/// nth 0 would just pass the very next
pub fn peekNextNth(self: *Self, nth: usize) ?*const u8 {
    if (self.pos + nth >= self.input.len) {
        return null;
    }
    return &self.input[self.pos + nth];
}

/// Reads characters until a whitespace is encountered
/// returns the amount of characters read
fn readWord(self: *Self) usize {
    const start_pos = self.pos;
    while (self.peekNext()) |ch| {
        log.info("next char: {c}", .{ch.*});
        const encountered_keyword = blk: {
            if (Token.FirstCharMap.get().get(ch.*)) |keywords| {
                for (keywords) |kw| {
                    const window_start = self.pos;
                    const window_end = window_start + kw.len;
                    log.info(
                        \\ Checking equality of: {s}
                        \\ and
                        \\ {s}
                    , .{ self.input[window_start..window_end], kw });
                    if (std.mem.eql(u8, self.input[window_start..window_end], kw)) {
                        const typ = Token.keyword_map.get(kw).?;
                        switch (typ) {
                            .in => break :blk std.ascii.isWhitespace((self.peekNext() orelse break :blk true).*),
                            else => break :blk true,
                        }
                    }
                    // break :blk false;
                }
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

/// progresses to next token, expecting a specific type
/// if any whitespace tokens are encountered they are skipped
/// returns SyntaxInvalid if next token doesn't match expected
pub fn expectNextNonWhitespace(self: *Self, typ: Token.Type) Error!Token {
    while (try self.nextToken()) |t| {
        if (t.typ.isWhitespace())
            continue;
        if (t.typ != typ)
            return error.SyntaxInvalid;
        return t;
    }
    return error.NoToken;
}

pub fn nextToken(self: *Self) Error!?Token {
    var slice_end: usize = self.pos + 1;
    var slice_start: usize = self.pos;

    const token_opt: ?Token = outer: while (self.progress()) |c| : (slice_end += 1) {
        log.info("Current char: {c}", .{c});
        switch (c) {
            ' ' => break :outer Token.create(" ", .space),
            '\n' => break :outer Token.create("\n", .newline),
            else => if (Token.FirstCharMap.get().get(c)) |keywords| {
                for (0..keywords.len) |i| {
                    const keyword = keywords[i];
                    log.info(
                        \\ Potential keyword: {s}
                    , .{keyword});

                    const typ = Token.keyword_map.get(keyword) orelse @panic("malformed FirstCharMap");
                    switch (typ) {
                        .json => if (self.prev_token orelse continue :outer != .access)
                            continue :outer,
                        .for_open, .for_close => if (self.prev_token orelse continue :outer != .marker_open)
                            continue :outer,
                        else => {},
                    }

                    if (is_keyword: {
                        for (1..keyword.len) |k| {
                            const peek = self.peekNextNth(k - 1) orelse break :is_keyword false;
                            log.info("Peek: {c}\nKeyword[k]: {c}", .{ peek.*, keyword[k] });
                            if (peek.* != keyword[k]) break :is_keyword false;
                        }
                        break :is_keyword true;
                    }) {
                        for (1..keyword.len) |_| {
                            _ = self.progress();
                            slice_end += 1;
                        }

                        break :outer Token.create(self.input[slice_start..slice_end], typ);
                    }
                }
            },
        }

        if (self.peekNext() != null)
            slice_end += self.readWord();

        const tok: Token.Type = blk: {
            const slice = self.input[slice_start..slice_end];
            // access tokens are always between markers and always start with a '.'
            // might be after an expression_open {{ or between markers
            if (self.between_markers and slice[0] == '.') break :blk .access;
            if (self.prev_token) |prev| switch (prev) {
                .expression_open => if (slice[0] == '.') break :blk .access,
                else => {},
            };

            break :blk Token.keyword_map.get(slice) orelse .literal;
        };

        break :outer Token.create(self.input[slice_start..slice_end], tok);
    } else {
        break :outer null;
    };
    slice_start = self.pos;

    if (token_opt) |token| {
        if (!token.typ.isWhitespace())
            self.prev_token = token.typ;

        if (token.typ == .marker_open)
            self.between_markers = true;

        if (token.typ == .marker_close) {
            if (!self.between_markers) {
                log.err(
                    \\ Encountered a .marker_close token before encountering a .marker_open token
                , .{});
                return error.SyntaxInvalid;
            }
            self.between_markers = false;
        }

        log.info("Got Token:\n{f}", .{token});
    }
    return token_opt;
}
