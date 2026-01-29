const std = @import("std");
const Scope = @import("Scope.zig");
const log = std.log.scoped(.Conditional);
const root = @import("root.zig");
const Allocator = std.mem.Allocator;
const Error = root.Error;

base_ptr: *const anyopaque,
/// @argument1: return value of `get`
/// @argument2: function pointer coerced to `*anyopaque`
/// @argument3: second argument of function coerced to `*anyopaque`
visitFunc: *const fn (Allocator, GetResult, *const anyopaque, *anyopaque) Error!void,
getFunc: *const fn (Conditional) GetResult,
const Conditional = @This();

const GetResult = union(enum) {
    bool: bool,
    payload: ?*const anyopaque,
};

pub fn get(self: Conditional) GetResult {
    return self.getFunc(self);
}

pub fn visit(
    self: Conditional,
    a: Allocator,
    item: GetResult,
    func: anytype,
    args: anytype,
) Error!void {
    return self.visitFunc(
        a,
        item,
        @ptrCast(func),
        @ptrCast(@constCast(args)),
    );
}

pub fn conditional(self: Conditional, allocator: Allocator, func: *const anyopaque, arg: *anyopaque) Error!Conditional {
    return self.conditionalFunc(allocator, self.get(), func, arg);
}

fn UnwrapConditionalChild(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .optional => |opt| opt.child,
        .bool => T,
        else => null,
    };
}

pub inline fn Builder(
    comptime T: type,
) error{NotConditional}!type {
    const CondChild = UnwrapConditionalChild(T) orelse return error.NotConditional;
    const IS_BOOL = @typeInfo(T) == .bool;

    return struct {
        pub fn init(ptr: *const anyopaque) Conditional {
            return .{
                .base_ptr = ptr,
                .visitFunc = &@This().visit,
                .getFunc = &@This().get,
            };
        }

        fn get(cond: Conditional) GetResult {
            if (IS_BOOL)
                return .{ .bool = @as(*const CondChild, @ptrCast(@alignCast(cond.base_ptr))) }
            else
                return .{ .payload = cond.base_ptr };
        }

        fn visit(
            a: Allocator,
            item: GetResult,
            f: *const anyopaque,
            args: *anyopaque,
        ) Error!void {
            const is_true = switch (item) {
                .bool => |b| b,
                .payload => |p| p != null,
            };
            if (!is_true) {
                log.warn("Conditional returned false", .{});
                return;
            }

            const scope: Scope = try switch (item) {
                .bool => |b| Scope.init(b, a),
                .payload => |po| if (po) |p|
                    Scope.init(@as(*const CondChild, @ptrCast(@alignCast(p))), a)
                else {
                    log.warn("Conditional payload empty", .{});
                    return;
                },
            };
            defer scope.deinit(a);
            const func: *const fn (Scope, *anyopaque) Error!void = @ptrCast(@alignCast(f));
            try func(scope, args);
        }
    };
}
