const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const log = std.log.scoped(.template);

const Error = error{ SyntaxInvalid, CannotSerialize } || std.mem.Allocator.Error || std.Io.Writer.Error;
const SerializeOptions = struct {
    field_name: []const u8,
    json: ?*const std.json.Stringify.Options = null,
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
    var prev_token: ?Token.Type = null;
    var current_access: ?SerializeOptions = null;

    while (try lexer.nextToken(a)) |token| {
        const dbg = try token.debugStr(a);
        defer a.free(dbg);
        switch (token.typ) {
            .literal => {
                try out.writer.writeAll(token.literal);
            },
            .access => {
                if (current_access) |_| return error.SyntaxInvalid;
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
                    try serializeField(context, &out.writer, opts);
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

inline fn handleStruct(parent: anytype, st: std.builtin.Type.Struct, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    inline for (st.fields) |f| {
        if (std.mem.eql(u8, f.name, opts.field_name)) {
            const field = @field(parent, f.name);
            const Ft = @TypeOf(field);

            writeType(Ft, field, writer, opts) catch |e| {
                log.err(
                    \\ Error: {any}
                    \\ Field Type: 
                ++
                    @typeName(Ft), .{e});
                return e;
            };
        }
    }
}

fn serializeField(
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
            return try handleStruct(parent_struct, st, writer, opts);
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => |st| return try handleStruct(parent_struct, st, writer, opts),
                else => log.warn("Parent type is not a pointer to struct, got: {any} ", .{@typeInfo(ptr.child)}),
            }
        },
        else => log.warn("Parent type is not a struct, got: {any} ", .{info}),
    }

    return error.CannotSerialize;
}
