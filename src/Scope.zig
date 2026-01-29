const std = @import("std");
const log = std.log.scoped(.Scope);
const comptimePrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;

const Iterator = @import("Iterator.zig");
const Conditional = @import("Conditional.zig");
const root = @import("root.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");

instance: *const anyopaque,
parent: ?*const Scope = null,
access_map: std.StaticStringMap(WriteAccessFunc),
child_scopes: std.StaticStringMap(GetInnerScopeFunc),
createIteratorFunc: ?*const fn (*const anyopaque) Iterator,
createConditionalFunc: ?*const fn (*const anyopaque) Conditional,
const Scope = @This();

pub const ScopeError = error{
    NotIterable,
    NotConditional,
    NotPresent,
} || util.WriteError || error{OutOfMemory};

const GetInnerScopeFunc = *const fn (
    Allocator,
    Scope,
) error{ OutOfMemory, NotPresent }!Scope;

const WriteAccessFunc = *const fn (
    *std.Io.Writer,
    Scope,
    std.json.Stringify.Options,
    bool,
) (util.WriteError || error{NotPresent})!void;

pub fn createIterator(self: @This()) error{NotIterable}!Iterator {
    return if (self.createIteratorFunc) |f| f(self.instance) else return error.NotIterable;
}
pub fn createConditional(self: @This()) error{NotConditional}!Conditional {
    return if (self.createConditionalFunc) |f| f(self.instance) else return error.NotConditional;
}

pub fn getChildScope(self_ptr: *const @This(), a: Allocator, key: []const u8) ScopeError!Scope {
    const func = self_ptr.*.child_scopes.get(key) orelse {
        log.err(
            \\ Tried to get child scope with key '{s}' but it was not present.
            \\ Scope: {any}
        , .{ key, self_ptr });
        return error.NotPresent;
    };
    var scope = try func(a, self_ptr.*);
    scope.parent = self_ptr;
    return scope;
}

pub fn getParentScope(self: @This(), depth: usize) error{NotPresent}!*const Scope {
    log.debug("GETTING {d} PARENT of {f}", .{ depth, self });
    if (depth == 1 or depth == 0) @panic("this function should not be called with values 0 or 1 for depth");
    var s = self.parent orelse return error.NotPresent;
    for (1..depth) |_| {
        s = s.parent orelse return error.NotPresent;
    }
    return s;
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

    if (self.parent) |parent|
        try writer.print(
            \\
            \\ Parent Scope:
            \\
            \\ {f}
        , .{parent.*})
    else
        try writer.writeAll("\nNo Parent Scope");
}

pub fn init(
    val: anytype,
    a: Allocator,
) error{OutOfMemory}!@This() {
    if (@typeInfo(@TypeOf(val)) != .pointer) @panic(
        \\ .init method expected `val` argument to be a pointer to some type
    );
    const DerefT = util.Deref(@TypeOf(val));
    const access_kvs = comptime accessMapKvs(DerefT, DerefT, ".");
    const child_kvs = comptime childScopesKvs(DerefT, DerefT, ".");

    log.debug(
        \\
        \\ {s} SCOPE INIT
    , .{@typeName(DerefT)});
    log.debug(
        \\ Access KVS
        \\
    , .{});
    for (access_kvs) |kv| {
        log.debug(
            \\ Key: {s}
            \\ Value: {any}
        , .{ kv.@"0", kv.@"1" });
    }

    log.debug(
        \\ Child Scopes KVS
        \\
    , .{});
    for (child_kvs) |kv| {
        log.debug(
            \\ Key: {s}
            \\ Value: {any}
        , .{ kv.@"0", kv.@"1" });
    }

    const IteratorBuilder: ?type = Iterator.Builder(DerefT) catch null;
    const ConditionalBuilder: ?type = Conditional.Builder(DerefT) catch null;

    const self = @This(){
        .instance = @ptrCast(val),
        .access_map = std.StaticStringMap(WriteAccessFunc).init(access_kvs, a) catch return error.OutOfMemory,
        .child_scopes = std.StaticStringMap(GetInnerScopeFunc).init(child_kvs, a) catch return error.OutOfMemory,
        .createIteratorFunc = if (IteratorBuilder) |B| B.init else null,
        .createConditionalFunc = if (ConditionalBuilder) |B| B.init else null,
    };
    return self;
}

pub fn deinit(self: @This(), a: Allocator) void {
    if (self.access_map.kvs.len > 0)
        self.access_map.deinit(a);
    if (self.child_scopes.kvs.len > 0)
        self.child_scopes.deinit(a);
}

pub fn getScopeAndAccess(self: *const @This(), access_literal: []const u8) error{NotPresent}!struct {
    *const Scope,
    []const u8,
} {
    log.debug(
        \\ SCOPE: {f}
        \\ ACCESS LITERAL: {s}
    , .{ self, access_literal });
    const periods_prefix_len = util.countPeriodsPrefix(access_literal);
    const lookup = access_literal[periods_prefix_len - 1 ..];
    const sc = if (periods_prefix_len == 1)
        self
    else
        self.getParentScope(periods_prefix_len) catch |e| {
            log.err(
                \\ SCOPE: {f}
                \\ DOES NOT HAVE A PARENT AT DEPTH {d}
            , .{ self, periods_prefix_len });
            return e;
        };

    return .{
        sc,
        lookup,
    };
}

/// checks if expressions are equal by comparing output of a writer against types
/// assumes `left` and `right` are access or literal expressions
pub fn evalComparison(self: @This(), a: Allocator, left: ast.ExpressionStatement, right: ast.ExpressionStatement) root.Error!bool {
    const writeExpr = struct {
        fn write(scope: *const Scope, w: *std.Io.Writer.Allocating, exp: @TypeOf(left)) (error{NotPresent} || util.WriteError)!void {
            switch (exp) {
                .access => |l| {
                    const sc, const lookup = try scope.getScopeAndAccess(l.literal);
                    try sc.*.access_map.get(lookup).?(&w.writer, sc.*, .{}, false);
                },
                .literal => |l| try switch (l.*) {
                    .boolean => |b| w.writer.print("{any}", .{b}),
                    .integer => |d| w.writer.print("{d}", .{d}),
                    .string => |s| w.writer.print("{s}", .{s}),
                },
                .comparison => @panic("evalComparison not implemented for comparison expressions"),
            }
        }
    }.write;

    var left_w = std.Io.Writer.Allocating.init(a);
    var right_w = std.Io.Writer.Allocating.init(a);
    defer {
        left_w.deinit();
        right_w.deinit();
    }

    try writeExpr(&self, &left_w, left);
    try writeExpr(&self, &right_w, right);

    log.debug("comparing buffers:\nleft: {s}\nright: {s}", .{ left_w.written(), right_w.written() });

    return std.mem.eql(u8, left_w.written(), right_w.written());
}

inline fn childScopesKvsCount(comptime Root: type, comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .@"struct" => blk: {
            comptime var i: usize = if (T == Root) 0 else 1;
            inline for (@typeInfo(T).@"struct".fields) |f| {
                const c = childScopesKvsCount(Root, f.type);
                i += c;
            }
            break :blk i;
        },
        .optional => 1,
        .pointer, .array => if (Root != T) 1 else 0,
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
            util.compileLogPrint(
                \\ Pushing {s} as root basename
            , .{basename});
            const func =
                flattenInstanceWalkerChainToGetChildScopeFunc(
                    T,
                    &buildInstanceWalkerFunctionChain(Root, basename),
                );
            tmp[0] = .{ basename, func };
        }

        switch (@typeInfo(T)) {
            .@"struct" => |st| {
                var i: usize = if (basename.len > 1) 1 else 0;
                for (st.fields) |f| {
                    util.compileLogPrint("FIELD: {s}", .{f.name});

                    const expected_size = childScopesKvsCount(Root, f.type);
                    if (expected_size == 0) {
                        util.compileLogPrint("SIZE == 0", .{});
                        continue;
                    }

                    const nested_basename = if (basename.len == 1)
                        basename ++ f.name
                    else
                        basename ++ "." ++ f.name;

                    const nested = childScopesKvs(Root, f.type, nested_basename);
                    for (nested) |kv| {
                        tmp[i] = kv;
                        i += 1;
                    }
                }
            },
            else => {},
        }

        if (tmp.len != OUT_SIZE) @compileError(comptimePrint(
            \\ entry count of of {s} does not match expected
            \\ i != {d}
        , .{ @typeName(T), OUT_SIZE }));

        break :blk tmp;
    };
    return arr;
}

inline fn accessMapKvsCount(comptime T: type) usize {
    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const N_NESTED = comptime blk: {
                var i: usize = 0;
                for (FIELDS) |f|
                    i += accessMapKvsCount(f.type) - 1;
                break :blk i;
            };

            return FIELDS.len + N_NESTED + 1;
        },
        else => return 1,
    }
}

inline fn accessMapKvs(
    comptime Root: type,
    comptime T: type,
    comptime basename: []const u8,
) [accessMapKvsCount(T)]struct { []const u8, WriteAccessFunc } {
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

            const inst = try flattenInstanceWalkerFunctionChain(
                &buildInstanceWalkerFunctionChain(Root, basename),
            )(s.instance);

            const val: *const T = @ptrCast(@alignCast(inst));
            try util.writeType(T, val.*, w, json_opts, print_json);
        }
    }.call;

    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const OUT_SIZE = accessMapKvsCount(T);

            const arr: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = comptime blk: {
                var tmp: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = undefined;
                tmp[0] = .{
                    basename,
                    accessBase,
                };
                var i: usize = 1;
                for (FIELDS) |f| {
                    const name = if (basename.len == 1)
                        comptimePrint("{s}{s}", .{ basename, f.name })
                    else
                        comptimePrint("{s}.{s}", .{ basename, f.name });

                    const entries = accessMapKvs(Root, f.type, name);
                    for (entries) |kv| {
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

const WalkToInstanceFunc = *const fn (*const anyopaque) error{NotPresent}!*const anyopaque;

inline fn buildInstanceWalkerChainItem(
    comptime T: type,
    comptime fieldname: []const u8,
) WalkToInstanceFunc {
    return &struct {
        fn call(inst: *const anyopaque) error{NotPresent}!*const anyopaque {
            log.debug(
                \\ Dereferencing ptr: {any} as {s}
            , .{ inst, @typeName(T) });
            if (!@hasField(T, fieldname)) return error.NotPresent;
            return @ptrCast(&@field(@as(*const T, @ptrCast(@alignCast(inst))), fieldname));
        }
    }.call;
}

inline fn buildInstanceWalkerFunctionChain(
    comptime Root: type,
    comptime basename: []const u8,
) [util.countPeriods(basename)]WalkToInstanceFunc {
    const fields = comptime basenameToFields(basename);
    comptime var funcs: [util.countPeriods(basename)]WalkToInstanceFunc = undefined;

    comptime var Ty: type = Root;
    inline for (fields, 0..) |name, i| {
        funcs[i] = buildInstanceWalkerChainItem(Ty, name);
        Ty = @FieldType(Ty, name);
    }
    return funcs;
}

inline fn flattenInstanceWalkerChainToGetChildScopeFunc(
    comptime T: type,
    comptime funcs: []const WalkToInstanceFunc,
) GetInnerScopeFunc {
    return &struct {
        fn call(
            a: Allocator,
            s: Scope,
        ) error{ OutOfMemory, NotPresent }!Scope {
            var inst: *const anyopaque = s.instance;
            inline for (funcs) |f| {
                inst = try f(inst);
            }
            return Scope.init(@as(*const T, @ptrCast(@alignCast(inst))), a);
        }
    }.call;
}

inline fn flattenInstanceWalkerFunctionChain(
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
