const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const log = std.log.scoped(.template);
const Error = @import("root.zig").Error;

const SerializeOptions = struct {
    field_name: []const u8,
    json: ?*const std.json.Stringify.Options = null,
    /// in case you want to access an nth item of an array field
    index: ?usize = null,
};

const ForScope = struct {
    current_index: usize = 0,
    closed: bool = false,
    current_access: ?SerializeOptions = null,
    writer: std.Io.Writer.Allocating,
    /// The identifier assigned to the field being accessed
    identifier: []const u8,
    /// The name of the actual field being accessed
    field_name: []const u8,
    start_pos: usize,
};

pub fn render(a: std.mem.Allocator, context: anytype, template_string: []const u8, json_opts: std.json.Stringify.Options) Error![]u8 {
    log.debug(
        \\ Attempting to render {s}:
        \\ {any}
        \\
    , .{ @typeName(@TypeOf(context)), context });
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
                if (current_access) |_| return error.SyntaxInvalid;
                log.debug("ACCESS TOKEN: {s}", .{token.literal});
                current_access = .{ .field_name = token.literal[1..] };
            },
            .json => {
                if (current_access == null)
                    return error.SyntaxInvalid;

                current_access.?.json = &json_opts;
                log.debug("current access token: {any}", .{current_access.?});
            },
            .marker_close => {
                if (current_access) |opts|
                    writeField(context, &out.writer, opts) catch |e| {
                        log.err(
                            \\ Failed to writefield: {any}
                        , .{e});
                        return e;
                    };
                current_access = null;
            },
            .newline, .space => {
                if (should_append: {
                    const t = prev_token orelse break :should_append true;
                    break :should_append switch (t) {
                        // whitespace within marker_open & marker_close should be ignored
                        .access, .json, .marker_open, .in, .for_open, .for_close => false,
                        else => true,
                    };
                }) {
                    try out.writer.writeByte(token.literal[0]);
                }
            },

            .for_open => {
                const next = try lexer.expectNextNonWhitespace(.literal);
                const variable_name = next.literal;
                _ = try lexer.expectNextNonWhitespace(.in);
                const field = try lexer.expectNextNonWhitespace(.access);
                _ = try lexer.expectNextNonWhitespace(.marker_close);
                const array_len = try arrayFieldLen(context, field.literal[1..]);
                const start_pos = lexer.pos;

                log.warn(
                    \\ For loop opened
                    \\ variable name: {s}
                    \\ field {s}
                    \\ len: {d}
                , .{ variable_name, field.literal[1..], array_len });

                var current_scope = ForScope{
                    .writer = std.Io.Writer.Allocating.init(a),
                    .start_pos = start_pos,
                    .identifier = variable_name,
                    .field_name = field.literal[1..],
                };
                defer current_scope.writer.deinit();

                var in_expression = false;
                for (0..array_len) |i| {
                    while (try lexer.nextToken()) |tok| {
                        log.warn(
                            \\On token: {any}
                        , .{tok.typ});
                        switch (tok.typ) {
                            .for_close => current_scope.closed = true,
                            .marker_close => if (current_scope.closed) break,
                            .expression_open => {
                                if (in_expression)
                                    return error.SyntaxInvalid
                                else
                                    in_expression = true;
                            },
                            .expression_close => {
                                if (current_scope.current_access) |*opts| {
                                    opts.index = i;
                                    switch (@typeInfo(@TypeOf(context))) {
                                        .@"struct" => |st| {
                                            inline for (st.fields) |f| {
                                                if (std.mem.eql(u8, f.name, current_scope.field_name)) {
                                                    const parent = @field(context, f.name);
                                                    writeField(parent, &current_scope.writer.writer, opts.*) catch |e| {
                                                        log.err(
                                                            \\ Failed to writefield: {any}
                                                        , .{e});
                                                        return e;
                                                    };
                                                }
                                            }
                                        },
                                        else => return null,
                                    }
                                }
                                current_scope.current_access = null;
                                try current_scope.writer.writer.writeByte('\n');
                                in_expression = false;
                            },
                            .access => {
                                if (!in_expression or current_scope.current_access != null) return error.SyntaxInvalid;
                                log.warn(
                                    \\ EXPRESSION: {any}
                                    \\ ACCESS: {any}
                                    \\ LITERAL: {s}
                                , .{ in_expression, current_scope.current_access, tok.literal });
                                // this isn't great. We aren't actually doing anything to map identifiers to the field name
                                // this will likely need to be changed
                                current_scope.current_access = .{ .field_name = current_scope.field_name, .index = i };
                            },
                            .json => {
                                if (!in_expression or current_scope.current_access == null) return error.SyntaxInvalid;
                                current_scope.current_access.?.json = &json_opts;
                            },

                            else => if (!in_expression and tok.typ == .literal)
                                try current_scope.writer.writer.writeAll(tok.literal),
                        }
                    }
                    log.warn("Got to end of loop {d}", .{i});
                    lexer.pos = current_scope.start_pos;
                }

                const slice = try current_scope.writer.toOwnedSlice();
                log.warn(
                    \\ Writing to writer:
                    \\ {s}
                , .{slice});
                try out.writer.writeAll(slice);

                defer a.free(slice);
            },

            else => {},
        }

        if (!token.typ.isWhitespace()) {
            prev_token = token.typ;
        }
        log.debug("buffer updated:\n[{s}]", .{out.written()});
    }
    log.debug("finished render\n", .{});
    return try out.toOwnedSlice();
}

inline fn writeType(T: type, inst: anytype, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    if (@TypeOf(inst) != T) @panic(@typeName(T) ++ " =! " ++ @typeName(@TypeOf(inst)));
    log.warn("Trying writetype: {s}", .{@typeName(T)});

    if (opts.json) |o|
        return try std.json.Stringify.value(inst, o.*, writer);

    const info = @typeInfo(T);
    switch (info) {
        .array => |a| {
            log.warn(
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

            log.warn("array child is not u8, got {s}", .{@typeName(a.child)});
            if (opts.index) |i| {
                var new_opts = opts;
                new_opts.index = null;
                try writeType(a.child, inst[i], writer, new_opts);
            }
        },
        .pointer => |ptr| {
            log.warn(
                \\ pointer type
            , .{});
            if (ptr.child == u8) {
                log.warn("size: {any}", .{ptr.size});
                switch (ptr.size) {
                    .slice => {
                        if (opts.index) |i| {
                            log.warn("Byte: {c}", .{inst[i]});
                            try writer.writeByte(inst[i]);
                        } else {
                            log.warn("Bytes: {s}", .{inst});
                            try writer.writeAll(inst);
                        }

                        return;
                    },
                    .one => return try writeType(ptr.child, inst.*, writer, opts),
                    else => return error.InvalidPointerType,
                }
            }

            log.warn("pointer child is not u8, got {s}", .{@typeName(ptr.child)});

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, opts);
        },
        .@"struct" => {
            log.warn(
                \\ struct type
            , .{});
            if (T == ArrayList(u8))
                return try if (opts.index) |i|
                    writer.writeByte(inst.items[i])
                else
                    writer.writeAll(inst.items);
        },
        else => {
            log.warn("No branch for handling {s}", .{@typeName(T)});
            return error.CannotSerialize;
        },
    }
}

inline fn writeStructField(parent: anytype, st: std.builtin.Type.Struct, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    switch (@typeInfo(@TypeOf(parent))) {
        .@"struct" => {},
        else => @compileError(
            \\ Incorrect parent type passed to writeStruct
            \\ Parent should be some struct, not 
        ++ @typeName(@TypeOf(parent))),
    }

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
    const info =
        @typeInfo(@TypeOf(parent_struct));
    log.warn(
        \\ trying to serialize field: {s}
        \\ TYPE: {s}
        \\ Options: 
        \\ json: {any}
        \\ index: {any}
    , .{ opts.field_name, @typeName(@TypeOf(parent_struct)), opts.json, opts.index });

    switch (info) {
        .@"struct" => |st| {
            return try writeStructField(parent_struct, st, writer, opts);
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => |st| {
                    switch (ptr.size) {
                        .one => return try writeStructField(parent_struct.*, st, writer, opts),
                        else => log.warn("child type is a struct but did not expect many item pointer: {any}", .{ptr.size}),
                    }
                },
                .array => |_| {
                    return try writeType(ptr.child, parent_struct.*, writer, opts);
                },
                else => log.warn("Parent type is not a pointer to struct, got: {any} ", .{@typeInfo(ptr.child)}),
            }
        },
        .array => |_| {
            return try writeType(@TypeOf(parent_struct), parent_struct, writer, opts);
        },
        else => log.warn("Parent type is not a struct, got: {any} ", .{info}),
    }

    return error.CannotSerialize;
}

fn arrayTypeLen(t: anytype) Error!usize {
    switch (@typeInfo(@TypeOf(t))) {
        .array => |a| return a.len,
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => return try arrayTypeLen(t.*),
                else => log.err("No branch for to handle pointer of size {any}", .{ptr.size}),
            }
        },
        else => log.err("No branch for getting array length for {s}", .{@typeName(@TypeOf(t))}),
    }
    return error.CannotIterate;
}

fn arrayFieldLen(
    parent_struct: anytype,
    field_name: []const u8,
) Error!usize {
    const info =
        @typeInfo(@TypeOf(parent_struct));

    switch (info) {
        .@"struct" => |st| {
            inline for (st.fields) |f| {
                if (std.mem.eql(u8, f.name, field_name)) {
                    const field = @field(parent_struct, f.name);
                    return arrayTypeLen(field);
                }
            }
        },
        else => log.err("No branch for getting array info for field {s} of {s}", .{ field_name, @typeName(@TypeOf(parent_struct)) }),
    }

    return error.CannotIterate;
}
