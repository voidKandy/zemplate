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
    *std.Io.Writer,
    Scope,
    std.json.Stringify.Options,
    bool,
) Error!void;

pub inline fn accessMapKvsCount(comptime T: type) usize {
    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const N_NESTED = blk: {
                comptime var i: usize = 0;
                inline for (FIELDS) |f|
                    i += accessMapKvsCount(f.type) - 1;
                break :blk i;
            };

            return FIELDS.len + N_NESTED + 1;
        },
        else => return 1,
    }
}

inline fn accessMapKvs(comptime T: type, comptime basename: []const u8) [accessMapKvsCount(T)]struct { []const u8, WriteAccessFunc } {
    const render_base: WriteAccessFunc = &struct {
        fn call(
            w: *std.Io.Writer,
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

            const OUT_SIZE = accessMapKvsCount(T);

            const arr: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = blk: {
                var tmp: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = undefined;
                tmp[0] = .{
                    basename,
                    render_base,
                };
                var i: usize = 1;
                inline for (FIELDS) |f| {
                    const name = if (basename.len == 1)
                        std.fmt.comptimePrint("{s}{s}", .{ basename, f.name })
                    else
                        std.fmt.comptimePrint("{s}.{s}", .{ basename, f.name });

                    const entries = accessMapKvs(f.type, name);
                    inline for (entries) |kv| {
                        tmp[i] = .{
                            kv.@"0",
                            kv.@"1",
                        };
                        i += 1;
                    }
                }
                break :blk tmp;
            };

            return arr;
        },
        else => return [1]struct { []const u8, WriteAccessFunc }{.{ basename, render_base }},
    }
}

pub const Scope = struct {
    instance: *const anyopaque,
    access_map: std.StaticStringMap(WriteAccessFunc),
    child_scopes: std.StaticStringMap(GetInnerScopeFunc),

    pub fn init(val: anytype, a: Allocator) error{OutOfMemory}!@This() {
        if (@typeInfo(@TypeOf(val)) != .pointer) @panic("NON POINTER TYPE PASSED TO FUNCTION");
        const DerefT = Deref(@TypeOf(val));
        const access_kvs = accessMapKvs(DerefT, ".");
        const child_kvs = childScopesKvs(DerefT);

        log.warn(
            \\SCOPE FOR {s} INIT
        , .{@typeName(DerefT)});
        for (access_kvs) |k| {
            log.warn(
                \\Access K: '{s}'
            , .{k.@"0"});
        }
        for (child_kvs) |k| {
            log.warn(
                \\Scope K: '{s}'
            , .{k.@"0"});
        }

        const self = @This(){
            .instance = @ptrCast(val),
            .access_map = std.StaticStringMap(WriteAccessFunc).init(access_kvs, a) catch return error.OutOfMemory,
            .child_scopes = std.StaticStringMap(GetInnerScopeFunc).init(child_kvs, a) catch return error.OutOfMemory,
        };
        return self;
    }

    pub fn deinit(self: @This(), a: Allocator) void {
        self.access_map.deinit(a);
        self.child_scopes.deinit(a);
    }
};
