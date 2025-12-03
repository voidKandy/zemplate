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
};

const ForScope = struct {
    current_index: usize = 0,
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
                    try writeField(context, &out.writer, opts);
                current_access = null;
            },
            .newline, .space => {
                if (should_append: {
                    const t = prev_token orelse break :should_append true;
                    break :should_append switch (t) {
                        // whitespace within marker_open & marker_close should be ignored
                        .access, .json, .marker_open => false,
                        else => true,
                    };
                }) {
                    try out.writer.writeByte(token.literal[0]);
                }
            },
            .for_open => {
                const start_pos = lexer.pos;
                const next = try lexer.expectNextNonWhitespace(.literal);
                const variable_name = next.literal;
                _ = try lexer.expectNextNonWhitespace(.in);
                const field = try lexer.expectNextNonWhitespace(.access);
                _ = try lexer.expectNextNonWhitespace(.marker_close);
                const array_len = try arrayFieldInfo(context, field.literal[1..]);

                var current_scope = ForScope{
                    .writer = std.Io.Writer.Allocating.init(a),
                    .start_pos = start_pos,
                    .identifier = variable_name,
                    .field_name = field.literal[1..],
                };

                var in_expression = false;
                for (0..array_len) |_| {
                    while (try lexer.nextToken()) |tok| {
                        switch (tok.typ) {
                            .expression_open => {
                                in_expression = true;
                            },
                            .expression_close => {
                                // const access = current_scope.current_access orelse return error.SyntaxInvalid;
                                // const amt_periods = std.mem.count(u8, access.field_name, ".");
                                // if (amt_periods == 1) {
                                //     var split = std.mem.splitScalar(u8, access.field_name, '.');
                                //     _ = split.first();
                                //     const field_access = @field(context, access.field_name);
                                //     const subfield_name = split.next().?;
                                //     const inner = @field(field_access, subfield_name);
                                //     var opts = current_scope.current_access.?;
                                //     opts.field_name = subfield_name;
                                //     try writeField(inner, current_scope.writer, opts);
                                // } else if (amt_periods == 0) {
                                //     try writeField(context, current_scope.writer, current_scope.current_access.?);
                                // } else {
                                //     log.err(
                                //         \\ zemplate currently only supports 1 layer of field access
                                //     , .{});
                                //     return error.SyntaxInvalid;
                                // }
                                in_expression = false;
                            },
                            .access => {
                                if (!in_expression or current_scope.current_access != null) return error.SyntaxInvalid;
                                current_scope.current_access = .{ .field_name = tok.literal[1..] };
                                // if (tok.literal[1..] == current_scope.identifier)
                                // current_scope.?.current_access = .{ .field_name = tok.literal[1..] };
                            },
                            .json => {
                                if (!in_expression or current_scope.current_access == null) return error.SyntaxInvalid;
                                current_scope.current_access.?.json = &json_opts;
                            },
                            else => if (!in_expression)
                                if (tok.typ.isWhitespace() or tok.typ == .literal)
                                    try current_scope.writer.writer.writeAll(tok.literal),
                        }
                    }
                }
            },

            .for_close => {},
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
    log.debug("Trying writetype: {s}", .{@typeName(T)});

    const info = @typeInfo(T);
    switch (info) {
        .array => |a| {
            if (a.child == u8) {
                return try if (a.sentinel()) |sent|
                    writer.writeAll(inst[0.. :sent])
                else
                    writer.writeAll(inst[0..]);
            }
        },
        .pointer => |ptr| {
            if (ptr.child == u8) {
                switch (ptr.size) {
                    .slice => return try writer.writeAll(inst),
                    .one => return try writeType(ptr.child, inst.*, writer, opts),
                    else => return error.InvalidPointerType,
                }
            }

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, opts);
        },
        .@"struct" => {
            if (T == ArrayList(u8)) return try writer.writeAll(inst.items);
        },
        else => {},
    }

    if (opts.json) |o|
        return try std.json.Stringify.value(inst, o.*, writer);

    return error.CannotSerialize;
}

inline fn writeStruct(parent: anytype, st: std.builtin.Type.Struct, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    var field_name = opts.field_name;
    var nested_field: ?[]const u8 = null;
    if (std.mem.lastIndexOfScalar(u8, opts.field_name, '.')) |i| {
        nested_field = field_name[i + 1 ..];
        field_name = field_name[0..i];
    }

    inline for (st.fields) |f| {
        // if (outer_field) |fname| {
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
        \\ trying to serialize field: [{s}]
        \\ Options:
        \\ Json: {any}
    , .{ opts.field_name, opts.json });
    const info =
        @typeInfo(@TypeOf(parent_struct));

    switch (info) {
        .@"struct" => |st| {
            return try writeStruct(parent_struct, st, writer, opts);
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => |st| return try writeStruct(parent_struct, st, writer, opts),
                else => log.warn("Parent type is not a pointer to struct, got: {any} ", .{@typeInfo(ptr.child)}),
            }
        },
        else => log.warn("Parent type is not a struct, got: {any} ", .{info}),
    }

    return error.CannotSerialize;
}

fn arrayFieldInfo(
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
                    const Ft = @TypeOf(field);
                    const f_info = @typeInfo(Ft);
                    switch (f_info) {
                        .array => |a| {
                            return a.len;
                        },
                        else => {},
                    }
                }
            }
        },
        else => {},
    }
    return error.CannotIterate;
}
