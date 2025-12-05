const std = @import("std");
const root = @import("root.zig");
const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = @import("Lexer.zig");
const Type = std.builtin.Type;
const Token = @import("Token.zig");
const log = std.log.scoped(.render);
const Error = @import("root.zig").Error;

const SerializeOptions = struct {
    field_name: []const u8,
    json: ?*const std.json.Stringify.Options = null,
    /// in case you want to access an nth item of an array field
    index: ?usize = null,
};

const ForScope = struct {
    arena: std.heap.ArenaAllocator,
    writer: std.Io.Writer.Allocating,
    /// The name of the actual field being accessed
    iterated_field_name: []const u8,
    /// Functions exactly like `prev_token` in the outermost `render` method
    prev_token: Token.Type,
    start_pos: usize,
    closed: bool = false,
    current_access: ?SerializeOptions = null,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ field name: {s}
            \\ prev token: {any}
            \\ start pos: {d}
            \\ closed: {any}
        , .{ self.iterated_field_name, self.prev_token, self.start_pos, self.closed });
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
        self.writer.deinit();
    }
};

pub fn Template(comptime Context: type) type {
    const context_type_info = @typeInfo(Context);
    const AMT_ITERABLE_FIELDS = blk: switch (context_type_info) {
        .@"struct" => |s| {
            var amt_cannot: usize = 0;
            inline for (s.fields) |f| {
                if (root.iterate.unwrapIterableChild(f.type) == null) amt_cannot += 1;
            }
            break :blk s.fields.len - amt_cannot;
        },
        else => @compileError("Cannot create template from " ++ @typeName(Context)),
    };

    const iterable_fields_arr: [AMT_ITERABLE_FIELDS]Type.StructField = blk: {
        var tmp: [AMT_ITERABLE_FIELDS]Type.StructField = undefined;
        var i: usize = 0;
        inline for (context_type_info.@"struct".fields) |f| {
            if (root.iterate.unwrapIterableChild(f.type) != null) {
                tmp[i] = f;
                i += 1;
            }
        }
        break :blk tmp;
    };

    const meta_fields: struct {
        un_fields: [AMT_ITERABLE_FIELDS]Type.UnionField,
        en_fields: [AMT_ITERABLE_FIELDS]Type.EnumField,
    } = blk: {
        var ufields: [AMT_ITERABLE_FIELDS]Type.UnionField = undefined;
        var efields: [AMT_ITERABLE_FIELDS]Type.EnumField = undefined;

        inline for (iterable_fields_arr, &ufields, &efields, 0..) |iter_fld, *unfld, *enfld, j| {
            const Typ = root.iterate.unwrapIterableChild(iter_fld.type).?;
            unfld.* = Type.UnionField{
                .alignment = @alignOf(Typ),
                .name = iter_fld.name,
                .type = Typ,
            };
            enfld.* = Type.EnumField{
                .value = j,
                .name = iter_fld.name,
            };
        }
        break :blk .{ .un_fields = ufields, .en_fields = efields };
    };

    const Tag =
        @Type(Type{
            .@"enum" = .{
                .fields = &meta_fields.en_fields,
                .tag_type = u32,
                .decls = &[_]Type.Declaration{},
                .is_exhaustive = true,
            },
        });
    const Union =
        @Type(Type{
            .@"union" = .{
                .fields = &meta_fields.un_fields,
                .decls = &[_]Type.Declaration{},
                .tag_type = Tag,
                .layout = .auto,
            },
        });

    const CreateFieldIterFunc = *const fn (std.mem.Allocator, *Context) *anyopaque;
    const DestroyFieldIterFunc = *const fn (std.mem.Allocator, *anyopaque) void;
    const NextItemFunc = *const fn (*anyopaque) ?Union;
    const IteratorWrapper = struct {
        createFunc: CreateFieldIterFunc,
        destroyFunc: DestroyFieldIterFunc,
        nextFunc: NextItemFunc,
    };

    var iterator_wrapper_arr: [AMT_ITERABLE_FIELDS]struct {
        []const u8,
        IteratorWrapper,
    } = undefined;

    inline for (iterable_fields_arr, &iterator_wrapper_arr) |f, *item| {
        item.*.@"0" = f.name;
        const T = root.iterate.StructFieldIterator(Context, f.name);

        const createFn = struct {
            fn fromParentWrapper(a: std.mem.Allocator, parent: *Context) *anyopaque {
                const instance = a.create(T) catch @panic("out of memory");
                instance.* = T.fromParentPtr(parent);
                const opaq: *anyopaque = @ptrCast(instance);
                return opaq;
            }
        }.fromParentWrapper;
        const destroyFn = struct {
            fn destroy(a: std.mem.Allocator, inst: *anyopaque) void {
                const instance: *T = @ptrCast(@alignCast(inst));
                a.destroy(instance);
            }
        }.destroy;
        const nextFn = struct {
            fn nextWrapper(inst: *anyopaque) ?Union {
                var instance: *T = @ptrCast(@alignCast(inst));
                const next = instance.next() orelse return null;
                return @unionInit(Union, f.name, next);
            }
        }.nextWrapper;
        item.@"1" = IteratorWrapper{
            .createFunc = createFn,
            .destroyFunc = destroyFn,
            .nextFunc = nextFn,
        };
    }

    const create_iterator_function_map = std.StaticStringMap(IteratorWrapper).initComptime(iterator_wrapper_arr);

    return struct {
        context: Context,
        const Self = @This();
        pub fn init(ctx: Context) Self {
            return .{ .context = ctx };
        }

        fn handleForOpen(self: *Self, lexer: *Lexer, a: std.mem.Allocator, json_opts: std.json.Stringify.Options) Error![]u8 {
            const field = try lexer.expectNextNonWhitespace(.access);
            _ = try lexer.expectNextNonWhitespace(.marker_close);
            const start_pos = lexer.pos;

            var current_scope = ForScope{
                .writer = std.Io.Writer.Allocating.init(a),
                .arena = std.heap.ArenaAllocator.init(a),
                .start_pos = start_pos,
                .prev_token = .marker_close,
                .iterated_field_name = field.literal[1..],
            };

            const iter_wrapper: ?IteratorWrapper = create_iterator_function_map.get(field.literal[1..]) orelse return error.CannotIterate;
            const iter = iter_wrapper.?.createFunc(a, &self.context);
            defer iter_wrapper.?.destroyFunc(a, iter);

            log.debug(
                \\ FOR LOOP OPENED
                \\ SCOPE: {f}
            , .{current_scope});

            defer current_scope.deinit();

            var true_position: ?usize = null;
            while (iter_wrapper.?.nextFunc(iter)) |n| {
                inline for (iterable_fields_arr) |f| {
                    if (std.mem.eql(u8, f.name, current_scope.iterated_field_name)) {
                        const next = @field(n, f.name);
                        try handleNext(next, lexer, &current_scope, json_opts);
                        current_scope.prev_token = .marker_close;
                        if (true_position == null) true_position = lexer.pos;
                        lexer.pos = current_scope.start_pos;
                    }
                }
            }
            log.debug(
                \\ FOR LOOP CLOSED
            , .{});
            lexer.pos = true_position.?;

            return current_scope.writer.toOwnedSlice();
        }

        pub fn render(self: *Self, a: std.mem.Allocator, template_string: []const u8, json_opts: std.json.Stringify.Options) Error![]u8 {
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
                            writeField(self.context, &out.writer, opts) catch |e| {
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
                            log.debug("Appending {any} after {any}", .{ token.typ, prev_token });
                            try out.writer.writeByte(token.literal[0]);
                        }
                    },

                    .for_open => {
                        const slice = try self.handleForOpen(&lexer, a, json_opts);
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

inline fn writeType(T: type, inst: anytype, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    if (@TypeOf(inst) != T) @panic(@typeName(T) ++ " =! " ++ @typeName(@TypeOf(inst)));
    log.debug("Trying writetype: {s}", .{@typeName(T)});

    if (opts.json) |o|
        return try std.json.Stringify.value(inst, o.*, writer);

    const info = @typeInfo(T);
    switch (info) {
        .array => |a| {
            log.debug(
                \\ array type
            , .{});
            if (a.child == u8) {
                const bytes =
                    if (a.sentinel()) |sent|
                        inst[0.. :sent]
                    else
                        inst[0..];

                if (opts.index) |i| {
                    log.debug("Byte: {c}", .{bytes[i]});
                    try writer.writeByte(bytes[i]);
                } else {
                    log.debug("Bytes: {s}", .{bytes});
                    try writer.writeAll(bytes);
                }
                return;
            }

            log.debug("array child is not u8, got {s}", .{@typeName(a.child)});
            if (opts.index) |i| {
                var new_opts = opts;
                new_opts.index = null;
                try writeType(a.child, inst[i], writer, new_opts);
            }
        },
        .pointer => |ptr| {
            log.debug(
                \\ pointer type
            , .{});
            if (ptr.child == u8) {
                log.debug("size: {any}", .{ptr.size});
                switch (ptr.size) {
                    .slice => {
                        if (opts.index) |i| {
                            log.debug("Byte: {c}", .{inst[i]});
                            try writer.writeByte(inst[i]);
                        } else {
                            log.debug("Bytes: {s}", .{inst});
                            try writer.writeAll(inst);
                        }

                        return;
                    },
                    .one => return try writeType(ptr.child, inst.*, writer, opts),
                    else => return error.InvalidPointerType,
                }
            }

            log.debug("pointer child is not u8, got {s}", .{@typeName(ptr.child)});

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, opts);
        },
        .@"struct" => {
            log.debug(
                \\ struct type
            , .{});
            if (T == ArrayList(u8)) {
                return try if (opts.index) |i|
                    writer.writeByte(inst.items[i])
                else
                    writer.writeAll(inst.items);
            } else {
                log.warn("No branch for handling {s}", .{@typeName(T)});
            }
        },
        .int => |int| {
            if (int.bits == @bitSizeOf(u8)) {
                return try writer.writeByte(inst);
            }
        },
        else => {},
    }
    log.warn("No branch for handling {s}", .{@typeName(T)});
    return error.CannotSerialize;
}

inline fn writeStructField(parent: anytype, st: std.builtin.Type.Struct, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    switch (@typeInfo(@TypeOf(parent))) {
        .@"struct" => {},
        else => @compileError(
            \\ Incorrect parent type passed to writeStruct
            \\ Parent should be some struct, not 
        ++ @typeName(@TypeOf(parent))),
    }

    log.debug(
        \\ Trying to write struct field
        \\ Struct: {s}
        \\ Field Name: {s}
    , .{ @typeName(@TypeOf(parent)), opts.field_name });

    var field_name = opts.field_name;
    var nested_field: ?[]const u8 = null;
    if (std.mem.lastIndexOfScalar(u8, opts.field_name, '.')) |i| {
        log.debug(
            \\ Detecting nested field access: {s}
        , .{opts.field_name});
        nested_field = field_name[i + 1 ..];
        field_name = field_name[0..i];
    }

    inline for (st.fields) |f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            const field = @field(parent, f.name);
            const Ft = @TypeOf(field);
            if (nested_field) |nested| {
                switch (@typeInfo(Ft)) {
                    .@"struct" => |nested_st| {
                        inline for (nested_st.fields) |nested_f| {
                            if (std.mem.eql(u8, nested_f.name, nested)) {
                                const nfield = @field(field, nested_f.name);
                                const Nft = @TypeOf(nfield);
                                var nested_opts = opts;
                                nested_opts.field_name = nested;
                                writeType(Nft, nfield, writer, nested_opts) catch |e| {
                                    log.err(
                                        \\ Field Type: {s}
                                        \\ Error: {any}
                                    , .{ @typeName(Ft), e });
                                    return e;
                                };
                            }
                        }
                    },
                    else => {
                        log.err("Nested field access only supported on structs!", .{});
                        return error.SyntaxInvalid;
                    },
                }
            } else {
                writeType(Ft, field, writer, opts) catch |e| {
                    log.err(
                        \\ Field Type: {s}
                        \\ Error: {any}
                    , .{ @typeName(Ft), e });
                    return e;
                };
            }
        }
    }
}

fn writeField(
    parent_struct: anytype,
    writer: *std.Io.Writer,
    opts: SerializeOptions,
) Error!void {
    log.debug(
        \\ Attempting writeField on {s}
        \\ Fieldname: {s}
    , .{ @typeName(@TypeOf(parent_struct)), opts.field_name });
    const info =
        @typeInfo(@TypeOf(parent_struct));

    switch (info) {
        .@"struct" => |st| {
            return try writeStructField(parent_struct, st, writer, opts);
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => |st| {
                    switch (ptr.size) {
                        .one => return try writeStructField(parent_struct.*, st, writer, opts),
                        else => log.debug("child type is a struct but did not expect many item pointer: {any}", .{ptr.size}),
                    }
                },
                .array => |_| {
                    return try writeType(ptr.child, parent_struct.*, writer, opts);
                },
                else => log.debug("Parent type is not a pointer to struct, got: {any} ", .{@typeInfo(ptr.child)}),
            }
        },
        .array => |_| {
            return try writeType(@TypeOf(parent_struct), parent_struct, writer, opts);
        },
        else => log.debug("Parent type is not a struct, got: {any} ", .{info}),
    }

    return error.CannotSerialize;
}

fn handleNext(
    next: anytype,
    lexer: *Lexer,
    scope: *ForScope,
    json_opts: std.json.Stringify.Options,
) Error!void {
    var in_expression = false;
    while (try lexer.nextToken()) |tok| {
        log.debug(
            \\On token: {any}
        , .{tok.typ});
        switch (tok.typ) {
            .for_close => scope.closed = true,
            .marker_close => if (scope.closed) return,
            .expression_open => {
                if (in_expression) {
                    log.err(
                        \\ Encountered an .expression_open token inside of an expression
                    , .{});
                    return error.SyntaxInvalid;
                } else in_expression = true;
            },
            .expression_close => {
                if (scope.current_access) |*opts| {
                    const fieldname_to_check = if (opts.field_name.len > 1) opts.field_name[1..] else null;

                    if (fieldname_to_check) |name| {
                        switch (@typeInfo(@TypeOf(next))) {
                            .@"struct" => |st| {
                                inline for (st.fields) |f| {
                                    if (std.mem.eql(u8, f.name, name)) {
                                        opts.field_name = name;
                                        writeField(next, &scope.writer.writer, opts.*) catch |e| {
                                            log.err(
                                                \\ Failed to writefield: {any}
                                            , .{e});
                                            return e;
                                        };
                                    }
                                }
                            },
                            else => return error.InvalidNext,
                        }
                    } else {
                        try writeType(@TypeOf(next), next, &scope.writer.writer, opts.*);
                    }
                }
                scope.current_access = null;
                in_expression = false;
            },
            .access => {
                if (!in_expression) {
                    log.err(
                        \\ Encountered .access token outside of an expression
                    , .{});
                    return error.SyntaxInvalid;
                }
                if (scope.current_access != null) {
                    log.err(
                        \\ Encountered .access token in loop before resolving previous
                    , .{});
                    return error.SyntaxInvalid;
                }
                log.debug(
                    \\ EXPRESSION: {any}
                    \\ ACCESS: {any}
                    \\ LITERAL: {s}
                , .{
                    in_expression,
                    scope.current_access,
                    tok.literal,
                });
                scope.current_access = .{
                    .field_name = tok.literal,
                };
            },
            .json => {
                if (!in_expression) {
                    log.err(
                        \\ Encountered .json token outside of an expression
                    , .{});
                    return error.SyntaxInvalid;
                }
                if (scope.current_access == null) {
                    log.err(
                        \\ Encountered .json token before an .access token
                    , .{});
                    return error.SyntaxInvalid;
                }
                scope.current_access.?.json = &json_opts;
            },

            else => if (!in_expression and (tok.typ == .literal or tok.typ.isWhitespace())) {
                if (should_append: {
                    if (!tok.typ.isWhitespace()) break :should_append true;
                    break :should_append switch (scope.prev_token) {
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
                    if (tok.typ.isWhitespace()) log.debug("Appending {any} after {any}", .{ tok.typ, scope.prev_token });
                    try scope.writer.writer.writeAll(tok.literal);
                }
            },
        }
        if (!tok.typ.isWhitespace()) scope.prev_token = tok.typ;
    }
}
