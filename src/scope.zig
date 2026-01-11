const std = @import("std");
const ast = @import("ast.zig");
const root = @import("root.zig");
const util = @import("util.zig");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.scope);
const comptimePrint = std.fmt.comptimePrint;
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

pub inline fn childScopesKvsCount(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .@"struct" => blk: {
            comptime var i: usize = 1;
            inline for (@typeInfo(T).@"struct".fields) |f| {
                // if (@typeInfo(f.type) == .@"struct") i += 1;
                // i += 1;
                const c = childScopesKvsCount(f.type);
                i += c;
            }
            break :blk i;
        },
        .pointer, .array => 1,
        else => 0,
    };
}

inline fn countPeriods(comptime string: []const u8) usize {
    comptime var i: usize = 0;

    inline for (string) |ch| {
        if (ch == '.') i += 1;
    }
    return i;
}

inline fn idxLastPeriod(comptime string: []const u8) usize {
    inline for (0..string.len) |i| {
        const idx = string.len - 1 - i;
        if (string[idx] == '.') return idx;
    }
    @panic("string contains no period");
}

const COMPILE_LOGS: bool = false;

inline fn compileLogPrint(comptime fmt: []const u8, args: anytype) void {
    if (COMPILE_LOGS) @compileLog(comptimePrint(fmt, args));
}

inline fn childScopesKvs(comptime Root: type, comptime T: type, comptime basename: []const u8) [childScopesKvsCount(T)]struct { []const u8, GetInnerScopeFunc } {
    compileLogPrint("GETTING KVS FOR {s} with {s}", .{ @typeName(T), basename });

    const amt_periods = countPeriods(basename);
    const idx_last_period = idxLastPeriod(basename);
    const call_base: GetInnerScopeFunc =
        if (basename.len == 1)
            &struct {
                fn call(
                    a: Allocator,
                    s: Scope,
                ) error{OutOfMemory}!Scope {
                    _ = a;
                    return s;
                }
            }.call
        else if (amt_periods == 1)
            &struct {
                fn call(
                    a: Allocator,
                    s: Scope,
                ) error{OutOfMemory}!Scope {
                    const inst: *const Root = @ptrCast(@alignCast(s.instance));
                    const field = @field(inst, basename[1..]);
                    return Scope.init(&field, a);
                }
            }.call
        else
            &struct {
                fn call(
                    a: Allocator,
                    s: Scope,
                ) error{OutOfMemory}!Scope {
                    const buildScopeFn = s.child_scopes.get(basename[0..idx_last_period]) orelse @panic(comptimePrint(
                        \\ {s} has no entry
                    , .{basename[0..idx_last_period]}));
                    const scope = try buildScopeFn(a, s);
                    const innerBuildScopeFn = scope.child_scopes.get(basename[idx_last_period..]) orelse @panic(comptimePrint(
                        \\ {s} has no entry
                    , .{basename[idx_last_period..]}));
                    return try innerBuildScopeFn(a, scope);
                }
            }.call;

    const OUT_SIZE = childScopesKvsCount(T);
    const arr: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = blk: {
        var tmp: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = undefined;
        if (OUT_SIZE == 0) break :blk tmp;

        tmp[0] = .{
            basename, call_base,
        };
        const info = @typeInfo(T);
        switch (info) {
            .pointer, .array => break :blk tmp,
            else => {},
        }

        var i: usize = 1;
        inline for (info.@"struct".fields) |f| {
            compileLogPrint("FIELD: {s}", .{f.name});
            const expected_size = childScopesKvsCount(f.type);
            if (expected_size == 0) {
                compileLogPrint("SIZE == 0", .{});
                continue;
            }

            const nested_basename = if (basename.len == 1)
                comptimePrint("{s}{s}", .{ basename, f.name })
            else
                comptimePrint("{s}.{s}", .{ basename, f.name });

            const entries = childScopesKvs(Root, f.type, nested_basename);

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
    const access_base: WriteAccessFunc = &struct {
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
                    access_base,
                };
                var i: usize = 1;
                inline for (FIELDS) |f| {
                    const name = if (basename.len == 1)
                        comptimePrint("{s}{s}", .{ basename, f.name })
                    else
                        comptimePrint("{s}.{s}", .{ basename, f.name });

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
        else => return [1]struct { []const u8, WriteAccessFunc }{.{ basename, access_base }},
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
        const child_kvs = childScopesKvs(DerefT, DerefT, ".");

        log.warn(
            \\SCOPE FOR {s} INIT
            \\
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
