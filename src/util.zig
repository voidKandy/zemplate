const std = @import("std");
const root = @import("root.zig");
const ArrayList = std.ArrayList;
const log = std.log.scoped(.util);
const Error = @import("root.zig").Error;
const JsonOptions = std.json.Stringify.Options;

/// using std.mem.eql on two comptime strings can sometimes return false positives
pub inline fn sliceEqualComptime(comptime a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    inline for (0..a.len) |i| {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub inline fn writeType(
    T: type,
    inst: anytype,
    writer: *std.Io.Writer,
    json_opts: JsonOptions,
    print_json: bool,
) Error!void {
    if (@TypeOf(inst) != T) @panic(@typeName(T) ++ " =! " ++ @typeName(@TypeOf(inst)));
    log.warn("Trying writetype: {s}", .{@typeName(T)});

    if (print_json)
        return try std.json.Stringify.value(inst, json_opts, writer);

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

                log.debug("Bytes: {s}", .{bytes});
                try writer.writeAll(bytes);
                return;
            }

            log.debug("array child is not u8, got {s}", .{@typeName(a.child)});
        },
        .pointer => |ptr| {
            log.debug(
                \\ pointer type
                \\ size: {any}
            , .{ptr.size});
            if (ptr.child == u8) {
                switch (ptr.size) {
                    .slice => {
                        log.warn("Bytes: {s}", .{inst});
                        try writer.writeAll(inst);

                        return;
                    },
                    .one => return try writeType(ptr.child, inst.*, writer, json_opts, print_json),
                    else => return error.InvalidPointerType,
                }
            }

            log.debug("pointer child is not u8, got {s}", .{@typeName(ptr.child)});

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, json_opts, print_json);
        },
        .@"struct" => |s| {
            log.debug(
                \\ struct type
            , .{});
            if (T == ArrayList(u8)) {
                return try writer.writeAll(inst.items);
            }

            inline for (s.fields) |fe| {
                log.debug(
                    \\ field '{s}' of {s}
                , .{ fe.name, @typeName(T) });
                writeType(fe.type, @field(inst, fe.name), writer, json_opts, print_json) catch |e| {
                    if (e != error.CannotSerialize) @panic(@errorName(e));
                    log.err(
                        \\ failing field '{s}'
                    , .{fe.name});
                };
            }

            return;
            // if (@hasDecl(T, "format"))
            //     return try inst.format(writer);
            // log.warn("No branch for handling {s}", .{@typeName(T)});
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
    field_name: []const u8,
    json_opts: std.json.Stringify.Options,
    print_json: bool,
) Error!void {
    log.debug(
        \\ Attempting writeField on {s}
        \\ Fieldname: {s}
    , .{ @typeName(@TypeOf(parent_struct)), field_name });
    const info =
        @typeInfo(@TypeOf(parent_struct));

    switch (info) {
        .@"struct" => |st| {
            return try writeStructField(
                parent_struct,
                st,
                writer,
                field_name,
                json_opts,
                print_json,
            );
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => |st| {
                    switch (ptr.size) {
                        .one => return try writeStructField(
                            parent_struct.*,
                            st,
                            writer,
                            field_name,
                            json_opts,
                            print_json,
                        ),
                        else => log.debug("child type is a struct but did not expect many item pointer: {any}", .{ptr.size}),
                    }
                },
                .array => |_| {
                    return try writeType(
                        ptr.child,
                        parent_struct.*,
                        writer,
                        json_opts,
                        print_json,
                    );
                },
                else => log.debug("Parent type is not a pointer to struct, got: {any} ", .{@typeInfo(ptr.child)}),
            }
        },
        .array => |_| {
            return try writeType(
                @TypeOf(parent_struct),
                parent_struct,
                writer,
                json_opts,
                print_json,
            );
        },
        else => log.debug("Parent type is not a struct, got: {any} ", .{info}),
    }

    return error.CannotSerialize;
}

inline fn writeStructField(
    parent: anytype,
    st: std.builtin.Type.Struct,
    writer: *std.Io.Writer,
    field_name: []const u8,
    json_opts: JsonOptions,
    print_json: bool,
) Error!void {
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
    , .{ @typeName(@TypeOf(parent)), field_name });

    //TODO
    // var nested_field: ?[]const u8 = null;
    // if (std.mem.lastIndexOfScalar(u8, field_name, '.')) |i| {
    //     log.debug(
    //         \\ Detecting nested field access: {s}
    //     , .{field_name});
    //     nested_field = field_name[i + 1 ..];
    //     field_name = field_name[0..i];
    // }

    inline for (st.fields) |f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            const field = @field(parent, f.name);
            const Ft = @TypeOf(field);
            // if (nested_field) |nested_field_name| {
            // } else {
            writeType(
                Ft,
                field,
                writer,
                json_opts,
                print_json,
            ) catch |e| {
                log.err(
                    \\ Field Type: {s}
                    \\ Error: {any}
                , .{ @typeName(Ft), e });
                return e;
            };
            //     switch (@typeInfo(Ft)) {
            //         .@"struct" => |nested_st| {
            //             inline for (nested_st.fields) |nested_f| {
            //                 if (std.mem.eql(u8, nested_f.name, nested_field_name)) {
            //                     const nfield = @field(field, nested_f.name);
            //                     const Nft = @TypeOf(nfield);
            //                     return writeType(
            //                         Nft,
            //                         nfield,
            //                         writer,
            //                         nested_field_name,
            //                         json_opts,
            //                         print_json,
            //                     ) catch |e| {
            //                         log.err(
            //                             \\ Field Type: {s}
            //                             \\ Error: {any}
            //                         , .{ @typeName(Ft), e });
            //                         return e;
            //                     };
            //                 }
            //             }
            //         },
            //         .array => |arr| {
            //             if (std.mem.eql(u8, nested_field_name, "len")) {
            //                 return writeType(
            //                     usize,
            //                     arr.len,
            //                     writer,
            //                     nested_field_name,
            //                     json_opts,
            //                     print_json,
            //                 ) catch |e|
            //                     {
            //                         log.err(
            //                             \\ Field Type: {s}
            //                             \\ Error: {any}
            //                         , .{ @typeName(Ft), e });
            //                         return e;
            //                     };
            //             }
            //         },
            //         .pointer => |ptr| {
            //             if (ptr.size == .slice and std.mem.eql(u8, nested_field_name, "len")) {
            //                 return writeType(
            //                     usize,
            //                     field.len,
            //                     writer,
            //                     nested_field_name,
            //                     json_opts,
            //                     print_json,
            //                 ) catch |e|
            //                     {
            //                         log.err(
            //                             \\ Field Type: {s}
            //                             \\ Error: {any}
            //                         , .{ @typeName(Ft), e });
            //                         return e;
            //                     };
            //             }
            //         },
            //         else => {},
            //     }

            //     log.err("Nested field access only supported on structs, slices and arrays!", .{});
            //     return error.SyntaxInvalid;
        }
        // }
    }
}
