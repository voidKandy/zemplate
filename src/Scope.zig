const std = @import("std");
const root = @import("root.zig");
const util = @import("util.zig");
const Iterator = @import("Iterator.zig");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Scope);
const comptimePrint = std.fmt.comptimePrint;

instance: *const anyopaque,
access_map: std.StaticStringMap(WriteAccessFunc),
child_scopes: std.StaticStringMap(GetInnerScopeFunc),
iterateFunc: error{NotIterable}!*const fn (@This()) Iterator,
const Scope = @This();

pub const ScopeError = error{
    NotIterable,
    NotConditional,
    NotPresent,
} || util.WriteError || error{OutOfMemory};

const GetInnerScopeFunc = *const fn (
    Allocator,
    Scope,
) error{OutOfMemory}!Scope;

const WriteAccessFunc = *const fn (
    *std.Io.Writer,
    Scope,
    std.json.Stringify.Options,
    bool,
) (util.WriteError || error{NotPresent})!void;

pub fn createIterator(self: @This()) error{NotIterable}!Iterator {
    return (try self.iterateFunc)(self);
}

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

pub fn init(
    val: anytype,
    a: Allocator,
) error{OutOfMemory}!@This() {
    if (@typeInfo(@TypeOf(val)) != .pointer) @panic(
        \\ .init method expected `val` argument to be a pointer to some type
    );
    const DerefT = util.Deref(@TypeOf(val));
    const access_kvs = accessMapKvs(DerefT, DerefT, ".");
    const child_kvs = childScopesKvs(DerefT, DerefT, ".");

    log.debug(
        \\ {s} SCOPE INIT
        \\
    , .{@typeName(DerefT)});

    const self = @This(){
        .instance = @ptrCast(val),
        .access_map = std.StaticStringMap(WriteAccessFunc).init(access_kvs, a) catch return error.OutOfMemory,
        .child_scopes = std.StaticStringMap(GetInnerScopeFunc).init(child_kvs, a) catch return error.OutOfMemory,
        .iterateFunc = blk: {
            const Builder = Iterator.Builder(DerefT) catch |e| break :blk e;
            break :blk &struct {
                fn call(scope: Scope) Iterator {
                    const info = Builder.ptrInfo(scope.instance);
                    return .{
                        .nextFunc = &Builder.next,
                        .visitFunc = &Builder.visit,
                        .base_ptr = info.base_ptr,
                        .len = info.len,
                    };
                }
            }.call;
        },
    };
    return self;
}

pub fn deinit(self: @This(), a: Allocator) void {
    if (self.access_map.kvs.len > 0)
        self.access_map.deinit(a);
    if (self.child_scopes.kvs.len > 0)
        self.child_scopes.deinit(a);
}

pub fn getChildScope(self: @This(), a: Allocator, key: []const u8) ScopeError!Scope {
    const func = self.child_scopes.get(key) orelse return error.NotPresent;
    return func(a, self);
}

pub fn writeAccess(
    self: @This(),
    key: []const u8,
    w: *std.Io.Writer,
    json_opts: std.json.Stringify.Options,
    print_json: bool,
) ScopeError!void {
    const func = self.access_map.get(key) orelse return error.NotPresent;
    return func(w, self, json_opts, print_json);
}

/// --- Private methods & Declarations for building Scope ---
///
///
inline fn childScopesKvsCount(comptime Root: type, comptime T: type) usize {
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

inline fn childScopesKvs(
    comptime Root: type,
    comptime T: type,
    comptime basename: []const u8,
) [childScopesKvsCount(Root, T)]struct { []const u8, GetInnerScopeFunc } {
    util.compileLogPrint("GETTING KVS FOR {s} with {s}", .{ @typeName(T), basename });

    const OUT_SIZE = childScopesKvsCount(Root, T);
    const arr: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = comptime blk: {
        var tmp: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = undefined;
        if (OUT_SIZE == 0) break :blk tmp;
        if (basename.len > 1) {
            tmp[0] = .{
                basename,
                flattenScopeWalkerFunctionChain(
                    &buildScopeWalkerFunctionChain(Root, basename),
                ),
            };
        }

        const info = @typeInfo(T);
        switch (info) {
            .pointer, .array => break :blk tmp,
            else => {},
        }

        var i: usize = if (basename.len > 1) 1 else 0;
        for (info.@"struct".fields) |f| {
            util.compileLogPrint("FIELD: {s}", .{f.name});

            const expected_size = childScopesKvsCount(Root, f.type);
            if (expected_size == 0) {
                util.compileLogPrint("SIZE == 0", .{});
                continue;
            }

            const nested_basename = if (basename.len == 1)
                comptimePrint("{s}{s}", .{ basename, f.name })
            else
                comptimePrint("{s}.{s}", .{ basename, f.name });

            const nested = childScopesKvs(Root, f.type, nested_basename);
            for (nested) |kv| {
                tmp[i] = kv;
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

inline fn basenameToFields(comptime basename: []const u8) [util.countPeriods(basename)][]const u8 {
    comptime var fields: [util.countPeriods(basename)][]const u8 = undefined;
    comptime var last = 1;
    comptime var k = 0;
    inline for (basename, 0..) |ch, i| {
        if (ch == '.') {
            if (i > last) {
                fields[k] = basename[last..i];
                k += 1;
                last = i + 1;
            } else last = i + 1;
        }
    }

    if (last < basename.len) {
        fields[k] = basename[last..];
        k += 1;
    }

    if (k != util.countPeriods(basename)) @compileError(comptimePrint(
        \\ Expected to have array of {d} fields got {d} for '{s}'
    , .{ util.countPeriods(basename), k, basename }));

    return fields;
}

inline fn buildScopeChainItem(
    comptime T: type,
    comptime fieldname: []const u8,
) GetInnerScopeFunc {
    return &struct {
        fn call(a: Allocator, s: Scope) error{OutOfMemory}!Scope {
            const inst: *const T = @ptrCast(@alignCast(s.instance));
            const field = @field(inst, fieldname);

            const scope = try Scope.init(&field, a);
            return scope;
        }
    }.call;
}

inline fn buildScopeWalkerFunctionChain(
    comptime Root: type,
    comptime basename: []const u8,
) [util.countPeriods(basename)]GetInnerScopeFunc {
    const fields = comptime basenameToFields(basename);
    comptime var funcs: [util.countPeriods(basename)]GetInnerScopeFunc = undefined;

    comptime var Ty: type = Root;
    inline for (fields, 0..) |name, i| {
        funcs[i] = buildScopeChainItem(Ty, name);
        Ty = @FieldType(Ty, name);
    }
    return funcs;
}

inline fn flattenScopeWalkerFunctionChain(
    comptime funcs: []const GetInnerScopeFunc,
) GetInnerScopeFunc {
    return &struct {
        fn call(
            a: Allocator,
            s: Scope,
        ) error{OutOfMemory}!Scope {
            var sc: Scope = s;
            inline for (funcs, 0..) |f, i| {
                sc = try f(a, sc);
                defer if (i < funcs.len - 1) sc.deinit(a);
            }
            return sc;
        }
    }.call;
}

const WalkToInstanceFunc =
    *const fn (*const anyopaque) error{NotPresent}!*const anyopaque;

inline fn buildAccessChainItem(
    comptime T: type,
    comptime fieldname: []const u8,
) WalkToInstanceFunc {
    return &struct {
        fn call(inst: *const anyopaque) error{NotPresent}!*const anyopaque {
            const val: *const T = @ptrCast(@alignCast(inst));
            if (!@hasField(T, fieldname)) return error.NotPresent;
            const field = @field(val, fieldname);
            return @ptrCast(&field);
        }
    }.call;
}

inline fn buildAccessWalkerFunctionChain(
    comptime Root: type,
    comptime basename: []const u8,
) [util.countPeriods(basename)]WalkToInstanceFunc {
    const fields = comptime basenameToFields(basename);
    comptime var funcs: [util.countPeriods(basename)]WalkToInstanceFunc = undefined;

    comptime var Ty: type = Root;
    inline for (fields, 0..) |name, i| {
        funcs[i] = buildAccessChainItem(Ty, name);
        Ty = @FieldType(Ty, name);
    }
    return funcs;
}

inline fn flattenAccessWalkerFunctionChain(
    comptime funcs: []const WalkToInstanceFunc,
) WalkToInstanceFunc {
    return &struct {
        fn call(inst: *const anyopaque) error{NotPresent}!*const anyopaque {
            var val: *const anyopaque = inst;
            inline for (funcs) |f| {
                val = try f(val);
            }
            return val;
        }
    }.call;
}

inline fn accessMapKvsCount(comptime T: type) usize {
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

inline fn accessMapKvs(comptime Root: type, comptime T: type, comptime basename: []const u8) [accessMapKvsCount(T)]struct { []const u8, WriteAccessFunc } {
    const accessBase: WriteAccessFunc = &struct {
        fn call(
            w: *std.Io.Writer,
            s: Scope,
            json_opts: std.json.Stringify.Options,
            print_json: bool,
        ) (util.WriteError || error{NotPresent})!void {
            if (basename.len == 1) {
                const val: *const Root = @ptrCast(@alignCast(s.instance));
                return try util.writeType(T, val.*, w, json_opts, print_json);
            }

            const inst = try flattenAccessWalkerFunctionChain(
                &buildAccessWalkerFunctionChain(Root, basename),
            )(s.instance);

            const val: *const T = @ptrCast(@alignCast(inst));
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
                    accessBase,
                };
                var i: usize = 1;
                inline for (FIELDS) |f| {
                    const name = if (basename.len == 1)
                        comptimePrint("{s}{s}", .{ basename, f.name })
                    else
                        comptimePrint("{s}.{s}", .{ basename, f.name });

                    const entries = accessMapKvs(Root, f.type, name);
                    inline for (entries) |kv| {
                        tmp[i] = kv;
                        i += 1;
                    }
                }
                break :blk tmp;
            };

            return arr;
        },
        else => return [1]struct { []const u8, WriteAccessFunc }{.{ basename, accessBase }},
    }
}

test "counts correct" {
    const Other = struct {
        numbers: []const u32,
    };

    const Inner = struct {
        string: []const u8,
        other: Other,
    };

    const Test = struct {
        id: i32,
        inner: Inner,
        arr: []const u8,
        others: []const Other,
    };

    const an = accessMapKvsCount(Test);
    if (an != 8) {
        std.log.err(
            \\ Expected 8 got: {d}
        , .{an});
        return error.Failure;
    }
    const cn = childScopesKvsCount(Test, Test);
    if (cn != 6) {
        std.log.err(
            \\ Expected 6 got: {d}
        , .{cn});
        return error.Failure;
    }
}

test "primitive scope Okay" {
    const scope = try Scope.init(&@as(u8, 42), std.testing.allocator);
    defer scope.deinit(std.testing.allocator);
}
