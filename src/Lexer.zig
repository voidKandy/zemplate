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
/// Marks if we are currently between statement_open and statement_close
in_statement: bool = false,
in_expression: bool = false,
in_string_literal: bool = false,

const Self = @This();

pub fn init(input: []const u8) Self {
    const l = Self{
        .input = input,
        .pos = 0,
    };

    Token.FirstCharMap.init() catch @panic("failed to initialize first char map");

    var iter = Token.FirstCharMap.get().iterator();
    while (iter.next()) |e| {
        log.debug("KEY '{c}': ", .{
            e.key_ptr.*,
        });
        for (e.value_ptr.*) |v| {
            log.debug("'{s}' ", .{
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
        \\ LEXER:
        \\ position: {d}
        \\ in_string_literal: {any}
        \\ in_expression: {any}
        \\ in_statement: {any}
    , .{ self.pos, self.in_string_literal, self.in_expression, self.in_statement });
    if (self.prev_token) |t| {
        try writer.print(
            \\ prev_token: {s}
        , .{@tagName(t)});
    }
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

/// Should only be called when inside a string literal
/// will consume everything until a ' is encountered
fn readStringLiteral(self: *Self) usize {
    const start_pos = self.pos;
    while (self.peekNext()) |ch| {
        if (ch.* == '\'') break;
        _ = self.progress();
    }
    return self.pos - start_pos;
}

/// Reads characters until a whitespace is encountered
/// returns the amount of characters read
fn readWord(self: *Self) usize {
    const start_pos = self.pos;
    while (self.peekNext()) |ch| {
        log.debug("next char: {c}", .{ch.*});
        const encountered_keyword = blk: {
            if (Token.FirstCharMap.get().get(ch.*)) |keywords| {
                for (keywords) |kw| {
                    const window_start = self.pos;
                    const window_end = window_start + kw.len;
                    if (window_end >= self.input.len) break :blk false;
                    log.debug(
                        \\ Checking equality of:
                        \\ '{s}'
                        \\ and
                        \\ '{s}'
                    , .{ self.input[window_start..window_end], kw });
                    if (std.mem.eql(u8, self.input[window_start..window_end], kw)) {
                        const typ = Token.keyword_map.get(kw).?;
                        // BAD? (smelly) exact line is called twice
                        if ((typ.isComparison() or typ == .if_open or typ == .if_close or typ == .@"else") and (!self.in_statement)) break :blk false;
                        break :blk true;
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
    var t = self.nextTokenSkipWhitespace();
    while (t.type != .eof) : (t = self.nextTokenSkipWhitespace()) {
        if (t.type != typ) {
            log.err(
                \\ Expected {any} token
                \\ Got {any}
            , .{ typ, t.type });
            return error.SyntaxInvalid;
        }
        return t;
    }
    return error.NoToken;
}

pub fn nextTokenSkipWhitespace(self: *Self) Token {
    var token = self.nextToken();
    while (token.type.isWhitespace()) {
        token = self.nextToken();
    }
    return token;
}

pub fn nextToken(self: *Self) Token {
    var slice_end: usize = self.pos + 1;
    const slice_start: usize = self.pos;
    const keyword_first_char_map = Token.FirstCharMap.get();

    const token_opt: ?Token = outer: while (self.progress()) |c| : (slice_end += 1) {
        switch (c) {
            ' ' => break :outer Token.create(" ", .space),
            '\n' => break :outer Token.create("\n", .newline),
            '\t' => break :outer Token.create("\t", .tab),
            '\'' => if (self.in_statement) break :outer Token.create("\'", .string_wrapper),
            else => {},
        }

        if (keyword_first_char_map.get(c)) |keywords| {
            for (keywords) |keyword| {
                const typ = Token.keyword_map.get(keyword) orelse @panic("malformed FirstCharMap");
                if ((typ.isComparison() or typ == .if_open or typ == .if_close or typ == .@"else") and (!self.in_statement)) break;

                switch (typ) {
                    .json => if (self.prev_token orelse continue :outer != .access)
                        continue :outer,
                    .for_open, .for_close => if (self.prev_token orelse continue :outer != .statement_open)
                        break,
                    // continue :outer,
                    else => {},
                }

                if (is_keyword: {
                    for (1..keyword.len) |k| {
                        const peek = self.peekNextNth(k - 1) orelse break :is_keyword false;
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
        }

        if (self.in_string_literal) {
            slice_end += self.readStringLiteral();
            break :outer Token.create(self.input[slice_start..slice_end], .literal);
        } else if (self.peekNext() != null)
            slice_end += self.readWord();

        const typ: Token.Type = blk: {
            const slice = self.input[slice_start..slice_end];
            // access tokens are always between markers and always start with a '.'
            // might be after an expression_open or between markers
            if ((self.in_statement or self.in_expression) and slice[0] == '.') break :blk .access;
            break :blk .literal;
        };

        break :outer Token.create(self.input[slice_start..slice_end], typ);
    } else {
        break :outer null;
    };

    const token = token_opt orelse return Token.EOF;

    if (!token.type.isWhitespace())
        self.prev_token = token.type;

    if (token.type == .statement_open)
        self.in_statement = true;

    if (token.type == .expression_open)
        self.in_expression = true;

    if (token.type == .string_wrapper) {
        self.in_string_literal = !self.in_string_literal;
    }

    if (token.type == .statement_close) {
        if (!self.in_statement) {
            log.err(
                \\ Encountered a .statement_close token before encountering a .statement_open token
            , .{});
        }
        self.in_statement = false;
    }

    if (token.type == .expression_close) {
        if (!self.in_expression) {
            log.err(
                \\ Encountered a .expression_close token before encountering a .expression_open token
            , .{});
        }
        self.in_expression = false;
    }

    log.debug("Got Token: {f}", .{token});
    return token;
}
