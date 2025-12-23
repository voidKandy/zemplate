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

pub fn Template(comptime Context: type) type {
    const IterationScope = struct {
        const IterCtx = @import("newiterate.zig").StructIterationContext(@This());

        arena: std.heap.ArenaAllocator,
        writer: std.Io.Writer.Allocating,
        iter_ctx: IterCtx,
        /// The name of the actual field being accessed
        iterated_field_name: []const u8,
        iterated_field: IterCtx.Field,
        // in the case that the iterated field is a struct
        // iterated_field_iter_ctx: ?IterCtx,
        lexer: *Lexer,
        start_pos: usize,
        closed: bool = false,
        current_access: ?SerializeOptions = null,
        /// Functions exactly like `prev_token` in the outermost `render` method
        prev_token: Token.Type,
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
            prev_token: Token.Type,
            json_opts: std.json.Stringify.Options,
        ) !@This() {
            if (@TypeOf(outer) != *OuterType) @compileError(std.fmt.comptimePrint(
                \\ Expected types to match
                \\ {s} != *{s}
            , .{ @typeName(@TypeOf(outer)), @typeName(OuterType) }));

            var iter_ctx = try IterCtx.init(OuterType, outer, a);
            // defer iter_ctx.deinit(a);
            log.warn("Created iteration context: {f}\n", .{iter_ctx});
            const field = iter_ctx.fields.get(iterated_field_name) orelse return error.CannotIterate;
            const field_iter_ctx = blk: {
                inline for (@typeInfo(OuterType).@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, iterated_field_name)) {
                        switch (@typeInfo(f.type)) {
                            .@"struct" => break :blk try IterCtx.init(f.type, &@field(outer, f.name), a),
                            else => {},
                        }
                    }
                }
                break :blk null;
            };
            _ = field_iter_ctx;
            const arena = std.heap.ArenaAllocator.init(a);
            const writer: std.Io.Writer.Allocating = .init(a);
            return @This(){
                .arena = arena,
                .writer = writer,
                .iter_ctx = iter_ctx,
                .iterated_field_name = iterated_field_name,
                .iterated_field = field,
                // .iterated_field_iter_ctx = field_iter_ctx,
                .start_pos = lexer.pos,
                .prev_token = prev_token,
                .lexer = lexer,
                .json_opts = json_opts,
            };
        }

        pub fn deinit(self: *@This(), a: Allocator) void {
            self.arena.deinit();
            self.writer.deinit();
            self.iter_ctx.deinit(a);
            // if (self.iterated_field_iter_ctx) |*ctx| {
            //     ctx.deinit(a);
            // }
        }

        fn handleForOpen(
            outer_type: type,
            outer: anytype,
            lexer: *Lexer,
            a: Allocator,
            json_opts: std.json.Stringify.Options,
        ) Error![]u8 {
            log.debug(
                \\ FOR LOOP OPENED
            , .{});
            const access = try lexer.expectNextNonWhitespace(.access);
            _ = try lexer.expectNextNonWhitespace(.marker_close);
            // const start_pos = lexer.pos;

            // var sani_literal_needs_freeing = false;

            const sani_literal = access.literal[1..];
            // defer if (sani_literal_needs_freeing) a.free(sani_literal);

            log.warn("Attempting to grab iterate for '{s}'", .{sani_literal});

            var scope: @This() = try .init(
                outer_type,
                outer,
                a,
                sani_literal,
                lexer,
                .marker_close,
                json_opts,
            );
            defer scope.deinit(a);

            var true_position: ?usize = null;

            while (scope.iterated_field.next()) |n| {
                log.warn("got next: {any}", .{n});
                try scope.iterated_field.visit(&scope, n);
                if (true_position == null) true_position = scope.lexer.pos;
                scope.lexer.pos = scope.start_pos;
                scope.prev_token = .marker_close;
            }

            log.debug(
                \\ FOR LOOP CLOSED
            , .{});
            lexer.pos = true_position.?;

            return scope.writer.toOwnedSlice();
        }

        pub fn visit(self: *@This(), val: anytype) Error!void {
            const visit_log = std.log.scoped(.visitor);
            var in_expression = false;
            while (try self.lexer.nextToken()) |tok| {
                visit_log.debug(
                    \\On token: {any}
                , .{tok.typ});
                switch (tok.typ) {
                    .for_open => {
                        const FieldType, const field = blk: {
                            inline for (@typeInfo(Context).@"struct".fields) |f| {
                                if (@import("iterate.zig").sliceEqualComptime(f.name, self.iterated_field_name) and @hasDecl(Context, f.name)) {
                                    const field = @field(Context, f.name);
                                    break :blk .{ @FieldType(Context, f.name), field };
                                }
                            }
                            return error.CannotIterate;
                        };
                        const bytes = try handleForOpen(
                            FieldType,
                            field,
                            self.lexer,
                            self.prev_token,
                            self.arena.allocator(),
                            self.json_opts,
                        );
                        // // const bytes = try handleForOpen(scope.*, lexer, a, json_opts);
                        try self.writer.writer.writeAll(bytes);
                    },
                    .for_close => self.closed = true,
                    .marker_close => if (self.closed) return,
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
                            const fieldname_to_check = if (opts.field_name.len > 1) opts.field_name[1..] else null;
                            const writeLambda = struct {
                                fn write(s: Type.Struct, fieldname_check: []const u8, v: anytype, writer: *std.Io.Writer, ser_opts: *SerializeOptions) anyerror!void {
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
                                            writeLambda(st, name, val, &self.writer.writer, opts) catch return error.CannotSerialize;
                                            break :write_field;
                                        },
                                        .pointer => |ptr| {
                                            if (ptr.size == .one) {
                                                switch (@typeInfo(ptr.child)) {
                                                    .@"struct" => |st| {
                                                        writeLambda(st, name, val.*, &self.writer.writer, opts) catch return error.CannotSerialize;
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
                                    , .{@typeInfo(@TypeOf(val))});
                                    return error.InvalidNext;
                                } else {
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
                            if (tok.typ == .space) visit_log.debug("{any} is before {any}", .{ self.prev_token, tok.typ });
                            break :should_append switch (self.prev_token) {
                                .expression_open,
                                .access,
                                .json,
                                .marker_open,
                                .for_close,
                                => false,
                                .marker_close => tok.typ == .space,
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

            while (try lexer.nextToken()) |token| {
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
                    .marker_close => {
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
                                // whitespace within marker_open & marker_close should be ignored
                                .access,
                                .json,
                                .marker_open,
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
                        const slice = try IterationScope.handleForOpen(
                            Context,
                            &self.context,
                            &lexer,
                            a,
                            json_opts,
                        );
                        defer a.free(slice);
                        prev_token = .marker_close;
                        log.debug(
                            \\ Writing to outer writer:
                            \\ [{s}]
                        , .{slice});
                        try out.writer.writeAll(slice);
                        // we cant have prev_token updated, so we continue
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
