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
    node: std.DoublyLinkedList.Node,

    const Self = @This();

    fn create(a: std.mem.Allocator, str: []u8, typ: TokenType) !*Self {
        const self = try a.create(Self);
        const content = try a.dupe(u8, str);
        self.* = .{ .content = content, .typ = typ, .node = std.DoublyLinkedList.Node{} };
        return self;
    }

    pub fn deinit(self: *Self, a: std.mem.Allocator) void {
        a.free(self.content);
    }
};

pub const Lexer = struct {
    input: []const u8,
    pos: usize,

    head: ?*Token = null,
    tail: ?*Token = null,
    const Self = @This();

    const MARKER_OPEN: []const u8 = "||zz";
    const MARKER_CLOSE: []const u8 = "zz||";

    pub fn init(input: []const u8) Self {
        const l = Lexer{
            .input = input,
            .pos = 0,
        };
        return l;
    }

    fn appendToken(self: *Self, tok: *Token) void {
        std.log.warn("Appending {any} token\n", .{tok.typ});
        if (tok.typ == .Block) {
            std.log.warn(
                \\
                \\ token is of Block type:
                \\ {s}
                \\
            , .{tok.content});
        }

        if (self.tail) |tail| {
            tail.node.next = &tok.node;
            tok.node.prev = &tail.node;
            self.tail = tok;
        } else {
            // first element
            self.head = tok;
            self.tail = tok;
            tok.node.prev = null;
            tok.node.next = null;
        }
    }

    pub fn debug(l: *Self) void {
        std.log.warn(
            \\ lexer:
            \\ position: {d}
            \\ next_position: {d}
            \\ char: {c}
            \\ input: {s}
        , .{ l.pos, l.next_pos, l.ch, l.input });
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

    /// Progresses through input, outputting the head of a linked list of tokens
    pub fn processInput(
        self: *Self,
        a: std.mem.Allocator,
    ) !void {
        // var token_stream: Token = undefined;
        var buffer = try ArrayList(u8).initCapacity(a, 1024 * 1024);
        defer buffer.deinit(a);

        var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            try buffer.append(a, c);
            current_byte = c;

            switch (c) {
                MARKER_OPEN[0] => {
                    for (1..MARKER_OPEN.len) |i| {
                        if (self.peekNext().?.* == MARKER_OPEN[i]) {
                            current_byte = self.progress();
                            try buffer.append(a, current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (0..MARKER_OPEN.len) |_| {
                        _ = buffer.pop();
                    }
                    const b =
                        try buffer.toOwnedSlice(a);
                    defer a.free(b);
                    const block_token = try Token.create(a, b, .Block);
                    self.appendToken(block_token);

                    var marker_token = try Token.create(
                        a,
                        @constCast(MARKER_OPEN),
                        .MarkerOpen,
                    );
                    prev_token = &marker_token.typ;
                    self.appendToken(marker_token);
                },

                MARKER_CLOSE[0] => {
                    for (1..MARKER_CLOSE.len) |i| {
                        if (self.peekNext().?.* == MARKER_CLOSE[i]) {
                            current_byte = self.progress();
                            try buffer.append(a, current_byte.?);
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
                    const b =
                        try buffer.toOwnedSlice(a);
                    defer a.free(b);
                    const token = try Token.create(a, b, typ);
                    self.appendToken(token);

                    var marker_token = try Token.create(a, @constCast(MARKER_CLOSE), .MarkerClose);
                    prev_token = &marker_token.typ;
                    self.appendToken(marker_token);
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
            const b =
                try buffer.toOwnedSlice(a);
            defer a.free(b);
            const token = try Token.create(a, b, typ);
            self.appendToken(token);
        }
    }
};
