const std = @import("std");
const ArrayList = std.ArrayList;

pub const TokenType = enum {
    Block,
    MarkerOpen,
    MarkerClose,
    Access,
};

pub const Token = struct {
    content: []u8,
    typ: TokenType,

    fn from_array_list(list: *ArrayList(u8), typ: TokenType) !Token {
        const content = try list.toOwnedSlice();
        return .{ .content = content, .typ = typ };
    }

    fn from_const_array(array: []const u8, typ: TokenType, allocator: std.mem.Allocator) !Token {
        var arraylist = ArrayList(u8).init(allocator);
        for (array) |v| {
            try arraylist.append(v);
        }
        return Token.from_array_list(&arraylist, typ);
    }

    fn into_node(self: @This(), allocator: std.mem.Allocator) !*Tokens.Node {
        const node = try allocator.create(Tokens.Node);
        node.* = Tokens.Node{ .data = self, .next = null };
        return node;
    }
};

pub const Tokens = std.DoublyLinkedList(Token);

pub const Lexer = struct {
    const Self = @This();
    input: []const u8,
    pos: usize,
    const MARKER_OPEN: []const u8 = "||zz";
    const MARKER_CLOSE: []const u8 = "zz||";

    pub fn init(input: []const u8) Self {
        const l = Lexer{
            .input = input,
            .pos = 0,
        };
        return l;
    }

    pub fn debug(l: *Self) void {
        std.log.warn("lexer:\nposition: {d}\nnext_position: {d}\nchar: {c}\ninput: {s}\n", .{ l.pos, l.next_pos, l.ch, l.input });
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
    pub fn peek_next(self: *Self) ?*const u8 {
        if (self.pos >= self.input.len) {
            return null;
        }
        return &self.input[self.pos];
    }

    /// Progresses through input, outputting the head of a linked list of tokens
    pub fn process_input(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !Tokens {
        var tokens = Tokens{ .first = null };
        var buffer = ArrayList(u8).init(allocator);
        defer buffer.deinit();

        var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            try buffer.append(c);
            current_byte = c;

            switch (c) {
                MARKER_OPEN[0] => {
                    for (1..MARKER_OPEN.len) |i| {
                        if (self.peek_next().?.* == MARKER_OPEN[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (0..MARKER_OPEN.len) |_| {
                        _ = buffer.pop();
                    }

                    var block_token = try Token.from_array_list(&buffer, TokenType.Block);
                    // std.log.warn("adding token with content: {s}\n", .{block_token.content});
                    tokens.prepend(try block_token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_OPEN, TokenType.MarkerOpen, allocator);
                    // std.log.warn("Adding open marker token\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                    // current_byte = self.progress();
                },

                MARKER_CLOSE[0] => {
                    for (1..MARKER_CLOSE.len) |i| {
                        if (self.peek_next().?.* == MARKER_CLOSE[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (0..MARKER_CLOSE.len) |_| {
                        _ = buffer.pop();
                    }

                    const typ = blk: {
                        if (prev_token) |t| {
                            if (t.* == TokenType.MarkerOpen) {
                                break :blk TokenType.Access;
                            }
                        }
                        break :blk TokenType.Block;
                    };
                    var token = try Token.from_array_list(&buffer, typ);
                    // std.log.warn("adding token with content: {s}\n", .{token.content});
                    tokens.prepend(try token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_CLOSE, TokenType.MarkerClose, allocator);
                    // std.log.warn("adding marker close\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                },
                else => {
                    // std.log.warn("matches none\nbuffer: [{s}]\n", .{buffer.items});
                },
            }
        }

        if (buffer.items.len > 0) {
            const typ = blk: {
                if (prev_token) |t| {
                    if (t.* == TokenType.MarkerOpen) {
                        break :blk TokenType.Access;
                    }
                }
                break :blk TokenType.Block;
            };
            var token = try Token.from_array_list(&buffer, typ);
            // std.log.warn("adding final token with content: {s}\n", .{token.content});
            tokens.prepend(try token.into_node(allocator));
        }

        return tokens;
    }
};
