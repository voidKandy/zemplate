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

pub inline fn childScopesKvsCount(comptime Root: type, comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .@"struct" => blk: {
            comptime var i: usize = if (T == Root) 0 else 1;
            inline for (@typeInfo(T).@"struct".fields) |f| {
                // if (@typeInfo(f.type) == .@"struct") i += 1;
                // i += 1;
                const c = childScopesKvsCount(Root, f.type);
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

    if (i == 0) @compileError(comptimePrint("counting periods on invalid input: {s}", .{string}));
    return i;
}

inline fn periodIdcs(comptime string: []const u8) [countPeriods(string)]usize {
    comptime var idcs: [countPeriods(string)]usize = undefined;
    comptime var i: usize = 0;

    inline for (string, 0..) |ch, k| {
        if (ch == '.') {
            idcs[i] = k;
            i += 1;
        }
    }

    if (i != countPeriods(string)) @compileError(comptimePrint(
        \\ period count of '{s}' does not match indices gotten
        \\ i != {d}
    , .{ string, countPeriods(string) }));

    return idcs;
}

const COMPILE_LOGS: bool = false;

inline fn compileLogPrint(comptime fmt: []const u8, args: anytype) void {
    if (COMPILE_LOGS) @compileLog(comptimePrint(fmt, args));
}

inline fn flattenScopeFunc(comptime Root: type, comptime basename: []const u8) GetInnerScopeFunc {
    const amt_periods = countPeriods(basename);

    if (amt_periods == 1)
        return &struct {
            fn call(
                a: Allocator,
                s: Scope,
            ) error{OutOfMemory}!Scope {
                const inst: *const Root = @ptrCast(@alignCast(s.instance));
                const field = @field(inst, basename[1..]);
                return Scope.init(&field, a);
            }
        }.call;

    return &struct {
        fn call(
            a: Allocator,
            s: Scope,
        ) error{OutOfMemory}!Scope {
            var scope = s;
            var func: ?GetInnerScopeFunc = null;

            comptime var Ty: type = Root;
            const period_idcs = periodIdcs(basename);

            inline for (0..amt_periods) |i| {
                const start = period_idcs[i];

                const end: ?usize = if (i + 1 >= amt_periods) null else period_idcs[i + 1];
                const inner_basename = if (end) |k| basename[start..k] else basename[start..];

                func = flattenScopeFunc(Ty, inner_basename);

                scope = try func.?(a, s);
                defer if (i < amt_periods - 1) scope.deinit(a);

                //when scope is constructed, it's new root is @FieldType(Ty, n)
                Ty = @FieldType(Ty, inner_basename[1..]);
            }
            return scope;
        }
    }.call;
}

inline fn childScopesKvs(comptime Root: type, comptime T: type, comptime basename: []const u8) [childScopesKvsCount(Root, T)]struct { []const u8, GetInnerScopeFunc } {
    compileLogPrint("GETTING KVS FOR {s} with {s}", .{ @typeName(T), basename });

    const call_base: ?GetInnerScopeFunc =
        if (basename.len == 1)
            null
        else
            flattenScopeFunc(Root, basename);

    const OUT_SIZE = childScopesKvsCount(Root, T);
    const arr: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = blk: {
        var tmp: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = undefined;
        if (OUT_SIZE == 0) break :blk tmp;
        if (call_base) |bs| {
            tmp[0] = .{
                basename, bs,
            };
        }

        const info = @typeInfo(T);
        switch (info) {
            .pointer, .array => break :blk tmp,
            else => {},
        }

        comptime var i: usize = if (call_base != null) 1 else 0;
        inline for (info.@"struct".fields) |f| {
            compileLogPrint("FIELD: {s}", .{f.name});
            const expected_size = childScopesKvsCount(Root, f.type);
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

        if (i != OUT_SIZE) @compileError(comptimePrint(
            \\ entry count of of {s} does not match expected
            \\ i != {d}
        , .{ @typeName(T), OUT_SIZE }));

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

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("Access Map:");
        for (self.access_map.keys()) |k| {
            try writer.print(
                \\
                \\ '{s}'
            , .{k});
        }
        try writer.writeAll("\nChild Scopes Map:");
        for (self.child_scopes.keys()) |k| {
            try writer.print(
                \\
                \\ '{s}'
            , .{k});
        }
    }
    pub fn init(val: anytype, a: Allocator) error{OutOfMemory}!@This() {
        if (@typeInfo(@TypeOf(val)) != .pointer) @panic("NON POINTER TYPE PASSED TO FUNCTION");
        const DerefT = Deref(@TypeOf(val));
        const access_kvs = accessMapKvs(DerefT, ".");
        const child_kvs = childScopesKvs(DerefT, DerefT, ".");

        log.warn(
            \\ {s} SCOPE INIT
            \\
        , .{@typeName(DerefT)});
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
