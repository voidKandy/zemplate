const std = @import("std");
const root = @import("root.zig");
const parse = root.parse;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Lexer = @import("Lexer.zig");
const Type = std.builtin.Type;
const Token = @import("Token.zig");
const log = std.log.scoped(.render);
const Error = @import("root.zig").Error;
const util = @import("util.zig");
const SerializeOptions = util.SerializeOptions;

const IterationScope = struct {
    const IterCtx = @import("iterate.zig").StructIterationContext(@This());

    arena: std.heap.ArenaAllocator,
    writer: std.Io.Writer.Allocating,
    /// In order to own the lifetimes of this we need to store it here
    /// it may look unused but do not remove!
    iter_ctx: IterCtx,
    /// The name of the actual field being accessed
    iterated_field_name: []const u8,
    iterated_field: IterCtx.Field,

    // outer_loop_vals: ?std.SinglyLinkedList = null,
    lexer: *Lexer,
    start_pos: usize,
    closed: bool = false,
    current_access: ?SerializeOptions = null,
    /// Functions exactly like `prev_token` in the outermost `render` method
    prev_token: Token.Type = .statement_close,
    json_opts: std.json.Stringify.Options,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ field name: {s}
            \\ prev token: {any}
            \\ start pos: {d}
            \\ closed: {any}
        , .{ self.iterated_field_name, self.prev_token, self.start_pos, self.closed });
    }

    pub fn init(
        OuterType: type,
        outer: anytype,
        a: Allocator,
        iterated_field_name: []const u8,
        lexer: *Lexer,
        json_opts: std.json.Stringify.Options,
    ) Error!@This() {
        if (@TypeOf(outer) != *OuterType) @compileError(std.fmt.comptimePrint(
            \\ Expected types to match
            \\ {s} != *{s}
        , .{ @typeName(@TypeOf(outer)), @typeName(OuterType) }));

        var iter_ctx = try IterCtx.init(OuterType, outer, a);
        // defer iter_ctx.deinit(a);
        log.debug("Created iteration context: \n{f}\n", .{iter_ctx});
        const field = iter_ctx.getField(iterated_field_name) orelse return error.CannotIterate;
        const arena = std.heap.ArenaAllocator.init(a);
        const writer: std.Io.Writer.Allocating = .init(a);
        return @This(){
            .arena = arena,
            .writer = writer,
            .iter_ctx = iter_ctx,
            .iterated_field_name = iterated_field_name,
            .iterated_field = field,
            .start_pos = lexer.pos,
            .lexer = lexer,
            .json_opts = json_opts,
        };
    }

    pub fn deinit(self: *@This(), a: Allocator) void {
        self.arena.deinit();
        self.writer.deinit();
        self.iter_ctx.deinit(a);
    }

    /// This function is what handles a "next iteration" of some field of the parent struct
    pub fn visit(self: *@This(), val: anytype) Error!void {
        const visit_log = std.log.scoped(.visitor);
        var in_expression = false;

        var tok = self.lexer.nextToken();
        while (tok.typ != .eof) : (tok = self.lexer.nextToken()) {
            visit_log.debug(
                \\On token: {any}
            , .{tok.typ});
            switch (tok.typ) {
                // BAD!! should follow same logic as handleForLoop
                .for_open => {
                    const slice = try handleForOpen(@TypeOf(val.*), @constCast(val), self.lexer, self.arena.allocator(), self.json_opts);

                    try self.writer.writer.writeAll(slice);
                },
                .for_close => self.closed = true,
                .statement_close => if (self.closed) return,
                .expression_open => {
                    if (in_expression) {
                        visit_log.err(
                            \\ Encountered an .expression_open token inside of an expression
                        , .{});
                        return error.SyntaxInvalid;
                    } else in_expression = true;
                },
                .expression_close => {
                    if (self.current_access) |*opts| {
                        const fieldname_to_check =
                            if (!std.mem.allEqual(u8, opts.field_name, '.') and opts.field_name.len > 1) opts.field_name[1..] else null;

                        // in order to accomodate for the fact that @TypeOf(val) might be a pointer
                        // im abstracting this function to make the switch statement below less ugly
                        const writeStructFieldLambda = struct {
                            fn write(s: Type.Struct, fieldname_check: []const u8, v: anytype, writer: *std.Io.Writer, ser_opts: *SerializeOptions) anyerror!void {
                                // very cringe that i have to do this
                                inline for (s.fields) |f| {
                                    if (std.mem.eql(u8, f.name, fieldname_check)) {
                                        ser_opts.field_name = fieldname_check;
                                        util.writeField(v, writer, ser_opts.*) catch |e| {
                                            visit_log.err(
                                                \\ Failed to writefield: {any}
                                            , .{e});
                                            return e;
                                        };
                                    }
                                }
                            }
                        }.write;
                        write_field: {
                            if (fieldname_to_check) |name| {
                                switch (@typeInfo(@TypeOf(val))) {
                                    .@"struct" => |st| {
                                        writeStructFieldLambda(st, name, val, &self.writer.writer, opts) catch return error.CannotSerialize;
                                        break :write_field;
                                    },
                                    .pointer => |ptr| {
                                        if (ptr.size == .one) {
                                            switch (@typeInfo(ptr.child)) {
                                                .@"struct" => |st| {
                                                    writeStructFieldLambda(st, name, val.*, &self.writer.writer, opts) catch return error.CannotSerialize;
                                                    break :write_field;
                                                },
                                                else => {},
                                            }
                                        }
                                    },
                                    else => {},
                                }
                                visit_log.err(
                                    \\ Expected the type of val to be a struct or pointer to single struct, got: {any}
                                    \\ Failed when looking for fieldname: '{s}' of {s}
                                , .{ @typeInfo(@TypeOf(val)), name, @typeName(@TypeOf(val)) });
                                return error.InvalidNext;
                            } else {
                                if (opts.field_name.len > 1) return error.SyntaxInvalid;
                                try util.writeType(@TypeOf(val), val, &self.writer.writer, opts.*);
                            }
                        }
                    }
                    self.current_access = null;
                    in_expression = false;
                },
                .access => {
                    if (!in_expression) {
                        visit_log.err(
                            \\ Encountered .access token outside of an expression
                        , .{});
                        return error.SyntaxInvalid;
                    }
                    if (self.current_access != null) {
                        visit_log.err(
                            \\ Encountered .access token in loop before resolving previous
                        , .{});
                        return error.SyntaxInvalid;
                    }
                    visit_log.debug(
                        \\ EXPRESSION: {any}
                        \\ ACCESS: {any}
                        \\ LITERAL: {s}
                    , .{
                        in_expression,
                        self.current_access,
                        tok.literal,
                    });
                    self.current_access = .{
                        .field_name = tok.literal,
                    };
                },
                .json => {
                    if (!in_expression) {
                        visit_log.err(
                            \\ Encountered .json token outside of an expression
                        , .{});
                        return error.SyntaxInvalid;
                    }
                    if (self.current_access == null) {
                        visit_log.err(
                            \\ Encountered .json token before an .access token
                        , .{});
                        return error.SyntaxInvalid;
                    }
                    self.current_access.?.json = &self.json_opts;
                },

                else => if (!in_expression and (tok.typ == .literal or tok.typ.isWhitespace())) {
                    if (should_append: {
                        if (!tok.typ.isWhitespace()) break :should_append true;
                        break :should_append switch (self.prev_token) {
                            .expression_open,
                            .access,
                            .json,
                            .statement_open,
                            .for_close,
                            => false,
                            .statement_close => tok.typ == .space,
                            else => true,
                        };
                    }) {
                        if (tok.typ.isWhitespace()) visit_log.debug("Appending {any} after {any}", .{ tok.typ, self.prev_token });
                        try self.writer.writer.writeAll(tok.literal);
                    }
                },
            }
            if (!tok.typ.isWhitespace()) self.prev_token = tok.typ;
        }
    }
};

fn handleForOpen(
    OuterType: type,
    outer: anytype,
    lexer: *Lexer,
    a: Allocator,
    json_opts: std.json.Stringify.Options,
) Error![]u8 {
    log.debug(
        \\ FOR LOOP OPENED
    , .{});
    const access = try lexer.expectNextNonWhitespace(.access);
    _ = try lexer.expectNextNonWhitespace(.statement_close);
    const sani_literal = access.literal[1..];

    log.debug("Attempting to grab iterate for '{s}'", .{sani_literal});

    var scope: IterationScope = try .init(
        OuterType,
        outer,
        a,
        sani_literal,
        lexer,
        json_opts,
    );
    defer scope.deinit(a);
    var true_position: ?usize = null;
    while (scope.iterated_field.next()) |n| {
        log.debug(
            \\ got next
            \\ addr: {any}
            \\ T: {s}
        , .{ n, @typeName(@TypeOf(n)) });
        try scope.iterated_field.visit(&scope, n);
        if (true_position == null) true_position = scope.lexer.pos;
        scope.lexer.pos = scope.start_pos;
        scope.prev_token = .statement_close;
    }

    log.debug(
        \\ FOR LOOP CLOSED
    , .{});
    scope.lexer.pos = true_position.?;

    return scope.writer.toOwnedSlice();
}

fn handleIfOpen(
    OuterType: type,
    outer: anytype,
    lexer: *Lexer,
    a: Allocator,
    json_opts: std.json.Stringify.Options,
) Error![]u8 {
    log.debug(
        \\ IF STATEMENT OPENED
    , .{});
    const access = try lexer.expectNextNonWhitespace(.access);
    _ = try lexer.expectNextNonWhitespace(.statement_close);
    const sani_literal = access.literal[1..];

    log.debug("Attempting to grab iterate for '{s}'", .{sani_literal});

    var scope: IterationScope = try .init(
        OuterType,
        outer,
        a,
        sani_literal,
        lexer,
        json_opts,
    );
    defer scope.deinit(a);
    var true_position: ?usize = null;
    while (scope.iterated_field.next()) |n| {
        log.debug(
            \\ got next
            \\ addr: {any}
            \\ T: {s}
        , .{ n, @typeName(@TypeOf(n)) });
        try scope.iterated_field.visit(&scope, n);
        if (true_position == null) true_position = scope.lexer.pos;
        scope.lexer.pos = scope.start_pos;
        scope.prev_token = .statement_close;
    }

    log.debug(
        \\ FOR LOOP CLOSED
    , .{});
    scope.lexer.pos = true_position.?;

    return scope.writer.toOwnedSlice();
}

pub fn Template(comptime Context: type) type {
    return struct {
        context: Context,
        const Self = @This();
        pub fn init(ctx: Context) Self {
            return .{ .context = ctx };
        }

        pub fn render(self: *Self, a: Allocator, template_string: []const u8, json_opts: std.json.Stringify.Options) Error![]u8 {
            log.debug(
                \\ Attempting to render {s}:
                \\ {any}
                \\
            , .{ @typeName(Context), self.context });
            var out: std.io.Writer.Allocating = .init(a);
            defer out.deinit();
            var lexer = Lexer.init(template_string[0..]);
            defer lexer.deinit();

            var prev_token: ?Token.Type = null;
            var current_access: ?SerializeOptions = null;

            var token = lexer.nextToken();
            while (token.typ != .eof) : (token = lexer.nextToken()) {
                switch (token.typ) {
                    .literal => {
                        try out.writer.writeAll(token.literal);
                    },
                    .access => {
                        if (current_access) |t| {
                            log.err(
                                \\ Encountered .access token for {s} before resolving previous: {s}
                            , .{ token.literal, t.field_name });
                            return error.SyntaxInvalid;
                        }
                        log.debug("ACCESS TOKEN: {s}", .{token.literal});
                        current_access = .{ .field_name = token.literal[1..] };
                    },
                    .json => {
                        if (current_access == null) {
                            log.err(
                                \\ Encountered .json token before an .access token
                            , .{});
                            return error.SyntaxInvalid;
                        }

                        current_access.?.json = &json_opts;
                        log.debug("current access token: {any}", .{current_access.?});
                    },
                    .statement_close => {
                        if (current_access) |opts|
                            util.writeField(self.context, &out.writer, opts) catch |e| {
                                log.err(
                                    \\ Failed to writefield: {any}
                                , .{e});
                                return e;
                            };
                        current_access = null;
                    },
                    .newline, .space, .tab => {
                        if (should_append: {
                            const t = prev_token orelse break :should_append true;
                            break :should_append switch (t) {
                                // whitespace within statement_open & statement_close should be ignored
                                .access,
                                .json,
                                .statement_open,
                                .for_open,
                                .for_close,
                                => false,
                                else => true,
                            };
                        }) {
                            try out.writer.writeAll(token.literal);
                        }
                    },

                    .for_open => {
                        const slice = try handleForOpen(Context, &self.context, &lexer, a, json_opts);
                        defer a.free(slice);
                        prev_token = .statement_close;
                        try out.writer.writeAll(slice);
                        continue;
                    },
                    .if_open => {
                        const slice = try handleIfOpen(Context, &self.context, &lexer, a, json_opts);
                        defer a.free(slice);
                        prev_token = .statement_close;
                        try out.writer.writeAll(slice);
                        continue;
                    },

                    else => {},
                }

                if (!token.typ.isWhitespace()) prev_token = token.typ;

                log.debug("buffer updated:\n[{s}]", .{out.written()});
            }
            log.debug("finished render\n", .{});
            return try out.toOwnedSlice();
        }
    };
}
