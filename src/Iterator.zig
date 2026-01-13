const std = @import("std");
const Scope = @import("scope.zig").Scope;
const log = std.log.scoped(.Iterator);
const root = @import("root.zig");
const Allocator = std.mem.Allocator;
const Error = root.Error;

/// @argument1: `Scope.instance`
nextFunc: *const fn (*@This()) ?*const anyopaque,
/// @argument1: return value of `nextFunc`
/// @argument2: function pointer coerced to `*anyopaque`
/// @argument3: second argument of function coerced to `*anyopaque`
visitFunc: *const fn (Allocator, *const anyopaque, *const anyopaque, *anyopaque) Error!void,
idx: usize = 0,
base_ptr: usize,
len: usize,

const Iterator = @This();

pub fn next(self: *@This()) ?*const anyopaque {
    return self.nextFunc(self);
}

pub fn visit(
    self: @This(),
    a: Allocator,
    item: *const anyopaque,
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

pub inline fn UnwrapIterableChild(comptime T: type) ?type {
    const info = @typeInfo(T);
    const child_opt: ?type = blk: {
        switch (info) {
            .array => |a| break :blk a.child,
            .pointer => |p| switch (p.size) {
                .slice => break :blk p.child,
                else => break :blk UnwrapIterableChild(p.child),
            },
            else => {},
        }
        break :blk null;
    };
    return child_opt;
}

pub inline fn Builder(
    comptime T: type,
) error{CannotIterate}!type {
    const type_info = @typeInfo(T);
    const ItemType = UnwrapIterableChild(T) orelse return error.CannotIterate;

    return struct {
        pub fn ptrInfo(ptr: *const anyopaque) struct {
            base_ptr: usize,
            len: usize,
        } {
            switch (type_info) {
                .array => |ar| {
                    // iter.ptr points to the array itself
                    return .{
                        .base_ptr = @intFromPtr(ptr),
                        .len = ar.len,
                    };
                },
                .pointer => |p| {
                    switch (p.size) {
                        .slice => {
                            // iter.ptr points to SLICE STRUCT, not data
                            const slice: *const T = @ptrCast(@alignCast(ptr));
                            return .{
                                .base_ptr = @intFromPtr(slice.ptr),
                                .len = slice.len,
                            };
                        },
                        else => {
                            log.err(
                                \\ No branch for pointer of size {s}
                            , .{@tagName(ptr.size)});
                            return null;
                        },
                    }
                },
                else => {
                    log.err(
                        \\ No branch for {s}
                    , .{@tagName(type_info)});
                    return null;
                },
            }
        }

        pub fn next(iter: *Iterator) ?*const anyopaque {
            if (iter.idx >= iter.len) return null;
            const item_ptr: *const anyopaque = @ptrFromInt(iter.base_ptr + iter.idx * @sizeOf(ItemType));

            _ = @as(*const ItemType, @ptrCast(@alignCast(item_ptr)));

            iter.idx += 1;

            return item_ptr;
        }

        pub fn visit(
            a: Allocator,
            item: *const anyopaque,
            f: *const anyopaque,
            args: *anyopaque,
        ) Error!void {
            const v: *const ItemType = @ptrCast(@alignCast(item));
            const scope = try Scope.init(ItemType, v, a);
            defer scope.deinit(a);
            const func: *const fn (Scope, *anyopaque) Error!void = @ptrCast(@alignCast(f));
            try func(scope, args);
        }
    };
}
