const std = @import("std");
const ArrayList = std.ArrayList;
const log = std.log.scoped(.parse);
const mem = std.mem;

pub const TokenType = enum {
    Block,
    MarkerOpen,
    MarkerClose,
    Json,
    Access,

    /// Some tokens are always the same literal
    fn literal(self: @This()) ?[]const u8 {
        return switch (self) {
            .Block, .Access => null,
            .MarkerOpen => "||zz",
            .MarkerClose => "zz||",
            .Json => "json",
        };
    }
};

pub const Token = struct {
    literal: []u8,
    typ: TokenType,
    node: std.DoublyLinkedList.Node,

    const Self = @This();

    fn create(a: mem.Allocator, str: []u8, typ: TokenType) !*Self {
        const self = try a.create(Self);
        const content = try a.dupe(u8, str);
        self.* = .{ .literal = content, .typ = typ, .node = std.DoublyLinkedList.Node{} };
        return self;
    }

    pub fn deinit(self: *Self, a: mem.Allocator) void {
        a.free(self.literal);
    }
};

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
    prev_token: ?*const TokenType = null,

    head: ?*Token = null,
    tail: ?*Token = null,
    const Self = @This();

    pub fn init(input: []const u8) Self {
        const l = Lexer{
            .input = input,
            .pos = 0,
        };
        return l;
    }

    fn appendToken(self: *Self, tok: *Token) void {
        log.debug("Appending {any} token\n", .{tok.typ});
        if (tok.typ == .Block) {
            log.debug(
                \\
                \\ token is of Block type:
                \\ {s}
                \\
            , .{tok.literal});
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
        log.debug(
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

    pub fn nextToken(self: *Self, a: mem.Allocator) ?Token {
        var buffer = try ArrayList(u8).initCapacity(a, 1024 * 1024);
        defer buffer.deinit(a);
        // var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            const possible_match =
                switch (c) {
                    TokenType.MarkerClose.literal().?[0] => TokenType.MarkerClose,
                    TokenType.MarkerOpen.literal().?[0] => TokenType.MarkerOpen,
                    TokenType.Json.literal().?[0] => TokenType.Json,
                    else => null,
                };

            if (possible_match) |tok| {
                const str = tok.literal();
                for (1..str.len) |i| {
                    if (self.peekNext().?.* != str[i])
                        continue :outer;
                    current_byte = self.progress();
                    try buffer.append(a, current_byte.?);
                }

                // if (mem.eql(u8, buffer, tok.literal()))
                //     return Token.create(a, , typ: TokenType)

                if (mem.endsWith(u8, buffer.items, str))
                    buffer.shrinkRetainingCapacity(buffer.items.len - str.len);

                // const typ = blk: {
                //     const t = self.prev_token orelse break :blk .Block;
                //     break :blk switch (t.*) {
                //         TokenType.MarkerOpen => .Access,
                //         else => tok,
                //     };
                // };

                // const b =
                //     try buffer.toOwnedSlice(a);
                // defer a.free(b);
                // const token = try Token.create(a, b, typ);
                // self.appendToken(token);

                // var marker_token = try Token.create(a, @constCast(MARKER_CLOSE), .MarkerClose);
                // prev_token = &marker_token.typ;
                // self.appendToken(marker_token);
            } else {
                buffer.append(a, c);
            }
        }
    }

    /// Progresses through input, outputting the head of a linked list of tokens
    pub fn processInput(
        self: *Self,
        a: mem.Allocator,
    ) !void {
        var buffer = try ArrayList(u8).initCapacity(a, 1024 * 1024);
        defer buffer.deinit(a);

        var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            try buffer.append(a, c);
            current_byte = c;

            switch (c) {
                TokenType.MarkerOpen.literal().?[0] => {
                    for (1..TokenType.MarkerOpen.literal().?.len) |i| {
                        if (self.peekNext().?.* == TokenType.MarkerOpen.literal().?[i]) {
                            current_byte = self.progress();
                            try buffer.append(a, current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }
                    if (mem.endsWith(u8, buffer.items, TokenType.MarkerOpen.literal().?)) {
                        buffer.shrinkRetainingCapacity(buffer.items.len - TokenType.MarkerOpen.literal().?.len);
                    }

                    const b =
                        try buffer.toOwnedSlice(a);
                    defer a.free(b);
                    const block_token = try Token.create(a, b, .Block);
                    self.appendToken(block_token);

                    const marker_token = try Token.create(
                        a,
                        @constCast(TokenType.MarkerOpen.literal().?),
                        .MarkerOpen,
                    );
                    prev_token = &marker_token.typ;
                    self.appendToken(marker_token);
                },

                TokenType.MarkerClose.literal().?[0] => {
                    for (1..TokenType.MarkerClose.literal().?.len) |i| {
                        if (self.peekNext().?.* == TokenType.MarkerClose.literal().?[i]) {
                            current_byte = self.progress();
                            try buffer.append(a, current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }
                    if (mem.endsWith(u8, buffer.items, TokenType.MarkerClose.literal().?)) {
                        buffer.shrinkRetainingCapacity(buffer.items.len - TokenType.MarkerClose.literal().?.len);
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

                    var marker_token = try Token.create(a, @constCast(TokenType.MarkerClose.literal().?), .MarkerClose);
                    prev_token = &marker_token.typ;
                    self.appendToken(marker_token);
                },
                else => {
                    // log.debug("matches none\nbuffer: [{s}]\n", .{buffer.items});
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
