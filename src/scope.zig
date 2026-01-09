const std = @import("std");
const ast = @import("ast.zig");
const root = @import("root.zig");
const util = @import("util.zig");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.scope);
const renderStatement = @import("render_context.zig").renderStatement;
const Error = root.Error;

fn Deref(comptime T: type) type {
    switch (@typeInfo(T)) {
        .pointer => |ptr| if (ptr.size == .one) return Deref(ptr.child) else return T,
        else => return T,
    }
}

const GetInnerScopeFunc = *const fn (
    Allocator,
    Scope,
    // *const anyopaque,
) error{OutOfMemory}!Scope;

inline fn childScopesKvs(comptime T: type) []const struct { []const u8, GetInnerScopeFunc } {
    const CallFunc = struct {
        fn getFunc(
            comptime Type: type,
            comptime field_name: []const u8,
        ) GetInnerScopeFunc {
            return &struct {
                fn call(
                    a: Allocator,
                    s: Scope,
                    // o: *const anyopaque,
                ) error{OutOfMemory}!Scope {
                    const inst: *const Type = @ptrCast(@alignCast(s.instance));
                    const field = @field(inst, field_name);
                    return Scope.init(&field, a);
                }
            }.call;
        }
    };

    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const N_FIELDS = blk: {
                comptime var i: usize = 0;
                inline for (FIELDS) |f| {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => |st| {
                            i += st.fields.len;
                            i += 1;
                        },
                        .pointer, .array => {
                            i += 1;
                        },
                        else => {},
                    }
                }
                break :blk i;
            };

            const arr: [N_FIELDS]struct { []const u8, GetInnerScopeFunc } = blk: {
                var tmp: [N_FIELDS]struct { []const u8, GetInnerScopeFunc } = undefined;
                if (N_FIELDS == 0) return &tmp;
                var i: usize = 0;
                inline for (FIELDS) |f| {
                    const field_info = @typeInfo(f.type);

                    switch (field_info) {
                        .@"struct", .pointer, .array => {},
                        else => continue,
                    }

                    tmp[i] = .{
                        std.fmt.comptimePrint(".{s}", .{f.name}),
                        CallFunc.getFunc(T, f.name),
                    };
                    i += 1;

                    if (field_info != .@"struct") continue;

                    inline for (field_info.@"struct".fields) |fld| {
                        tmp[i] = .{
                            std.fmt.comptimePrint(".{s}.{s}", .{ f.name, fld.name }),
                            // &struct {
                            //     fn call(
                            //         a: Allocator,
                            //         o: *anyopaque,
                            //     ) error{OutOfMemory}!Scope {
                            //         const inst: *T = @ptrCast(@alignCast(o));
                            //         const field = @field(inst, f.name);
                            //         const nested_field = @field(field, fld.name);
                            //         CallFunc.getFunc(@TypeOf(field), fld.name)(nested_field, a);
                            //     }
                            // }.call,
                            CallFunc.getFunc(f.type, fld.name),
                        };

                        i += 1;
                    }
                }
                break :blk tmp;
            };

            return &arr;
        },

        else => return &[_]struct { []const u8, GetInnerScopeFunc }{},
    }
}

const WriteAccessFunc = *const fn (
    // Allocator,
    *std.Io.Writer,
    Scope,
    // *const anyopaque,
    // ast.Statement,
    std.json.Stringify.Options,
    bool,
) Error!void;

inline fn accessMapKvs(comptime T: type) []const struct { []const u8, WriteAccessFunc } {
    const CallFunc = struct {
        fn getFunc(
            comptime Type: type,
            comptime field_name: []const u8,
        ) WriteAccessFunc {
            return &struct {
                fn call(
                    w: *std.Io.Writer,
                    // o: *const anyopaque,
                    s: Scope,
                    json_opts: std.json.Stringify.Options,
                    print_json: bool,
                ) Error!void {
                    log.warn(
                        \\ '{s}': {s}
                    , .{ @typeName(Type), field_name });
                    const val: *const Type = @ptrCast(@alignCast(s.instance));
                    const fld = @field(val, field_name);
                    try util.writeType(@FieldType(T, field_name), fld, w, json_opts, print_json);
                }
            }.call;
        }
    };

    const render_base_key = ".";
    const render_base: WriteAccessFunc = &struct {
        fn call(
            w: *std.Io.Writer,
            // o: *const anyopaque,
            s: Scope,
            json_opts: std.json.Stringify.Options,
            print_json: bool,
        ) Error!void {
            const val: *const T = @ptrCast(@alignCast(s.instance));
            try util.writeType(T, val.*, w, json_opts, print_json);
        }
    }.call;

    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const N_NESTED = blk: {
                comptime var i: usize = 0;
                inline for (FIELDS) |f| {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => |st| {
                            i += st.fields.len;
                        },
                        else => {
                            // i += 1;
                        },
                    }
                }
                break :blk i;
            };

            const MAP_SIZE = FIELDS.len + N_NESTED + 1;

            // // @compileLog(std.fmt.comptimePrint(
            //     \\ Constructing access funcs for {s}
            // , .{@typeName(T)}));
            // // @compileLog(std.fmt.comptimePrint(
            //     \\ MAP_SIZE: {d}
            // , .{MAP_SIZE}));
            const arr: [MAP_SIZE]struct { []const u8, WriteAccessFunc } = blk: {
                var tmp: [MAP_SIZE]struct { []const u8, WriteAccessFunc } = undefined;
                tmp[0] = .{
                    render_base_key,
                    render_base,
                };
                var i: usize = 1;
                inline for (FIELDS) |f| {
                    {
                        const name =
                            std.fmt.comptimePrint(".{s}", .{f.name});
                        tmp[i] = .{
                            name,
                            CallFunc.getFunc(T, f.name),
                        };
                    }
                    i += 1;

                    switch (@typeInfo(f.type)) {
                        .@"struct" => |st| {
                            inline for (st.fields) |fld| {
                                {
                                    const name =
                                        std.fmt.comptimePrint(".{s}.{s}", .{ f.name, fld.name });
                                    tmp[i] = .{
                                        name,
                                        CallFunc.getFunc(f.type, fld.name),
                                    };
                                }

                                i += 1;
                            }
                        },
                        else => {},
                    }
                }
                break :blk tmp;
            };

            return &arr;
        },
        else => return &[_]struct { []const u8, WriteAccessFunc }{.{ render_base_key, render_base }},
    }
}

pub const Scope = struct {
    instance: *const anyopaque,
    access_map: std.StaticStringMap(WriteAccessFunc),
    child_scopes: std.StaticStringMap(GetInnerScopeFunc),

    pub fn init(val: anytype, a: Allocator) error{OutOfMemory}!@This() {
        if (@typeInfo(@TypeOf(val)) != .pointer) @panic("NON POINTER TYPE PASSED TO FUNCTION");
        const DerefT = Deref(@TypeOf(val));
        const self = @This(){
            .instance = @ptrCast(val),
            .access_map = std.StaticStringMap(WriteAccessFunc).init(accessMapKvs(DerefT), a) catch return error.OutOfMemory,
            .child_scopes = std.StaticStringMap(GetInnerScopeFunc).init(childScopesKvs(DerefT), a) catch return error.OutOfMemory,
        };
        log.warn(
            \\SCOPE FOR {s} INIT
        , .{@typeName(DerefT)});
        for (self.access_map.keys()) |k| {
            log.warn(
                \\Access K: {s}
            , .{k});
        }
        for (self.child_scopes.keys()) |k| {
            log.warn(
                \\Scope K: {s}
            , .{k});
        }
        return self;
    }
};
