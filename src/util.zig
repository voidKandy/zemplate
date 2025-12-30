const std = @import("std");
const root = @import("root.zig");
const ArrayList = std.ArrayList;
const log = std.log.scoped(.util);
const Error = @import("root.zig").Error;

pub const SerializeOptions = struct {
    field_name: []const u8,
    json: ?*const std.json.Stringify.Options = null,
    /// in case you want to access an nth item of an array field
    index: ?usize = null,
};

/// using std.mem.eql on two comptime strings can sometimes return false positives
pub inline fn sliceEqualComptime(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    inline for (a, 0..) |c, i| {
        if (c != b[i]) return false;
    }
    return true;
}

pub inline fn writeType(T: type, inst: anytype, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
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
            return try if (int.bits == @bitSizeOf(u8))
                writer.writeByte(inst)
            else
                writer.print("{d}", .{inst});
        },
        else => {},
    }
    log.warn("No branch for handling {s}", .{@typeName(T)});
    return error.CannotSerialize;
}

pub fn writeField(
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
                                return writeType(Nft, nfield, writer, nested_opts) catch |e| {
                                    log.err(
                                        \\ Field Type: {s}
                                        \\ Error: {any}
                                    , .{ @typeName(Ft), e });
                                    return e;
                                };
                            }
                        }
                    },
                    .array => |arr| {
                        if (std.mem.eql(u8, nested, "len")) {
                            return writeType(usize, arr.len, writer, opts) catch |e|
                                {
                                    log.err(
                                        \\ Field Type: {s}
                                        \\ Error: {any}
                                    , .{ @typeName(Ft), e });
                                    return e;
                                };
                        }
                    },
                    .pointer => |ptr| {
                        if (ptr.size == .slice and std.mem.eql(u8, nested, "len")) {
                            return writeType(usize, field.len, writer, opts) catch |e|
                                {
                                    log.err(
                                        \\ Field Type: {s}
                                        \\ Error: {any}
                                    , .{ @typeName(Ft), e });
                                    return e;
                                };
                        }
                    },
                    else => {},
                }

                log.err("Nested field access only supported on structs, slices and arrays!", .{});
                return error.SyntaxInvalid;
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
