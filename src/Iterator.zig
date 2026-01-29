const std = @import("std");
const Scope = @import("Scope.zig");
const log = std.log.scoped(.Iterator);
const root = @import("root.zig");
const Allocator = std.mem.Allocator;
const Error = root.Error;

idx: usize = 0,
base_ptr: *const anyopaque,
stride: usize,
len: usize,
/// @argument1: return value of `next`
/// @argument2: function pointer coerced to `*anyopaque`
/// @argument3: second argument of function coerced to `*anyopaque`
visitFunc: *const fn (Allocator, *const anyopaque, *const anyopaque, *anyopaque) Error!void,

const Iterator = @This();

pub fn next(self: *@This()) ?*const anyopaque {
    if (self.idx >= self.len) return null;
    const item_ptr: *const anyopaque = @ptrFromInt(@intFromPtr(self.base_ptr) + self.idx * self.stride);

    self.idx += 1;

    return item_ptr;
}

pub fn format(self: Iterator, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("Iterator {{ base_ptr = {any}, idx = {}, len = {} }}", .{ self.base_ptr, self.idx, self.len });
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

inline fn UnwrapIterableChild(comptime T: type) ?type {
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
) error{NotIterable}!type {
    const type_info = @typeInfo(T);
    const ItemType = UnwrapIterableChild(T) orelse return error.NotIterable;
    const stride = @sizeOf(ItemType);

    const PointerInfo =
        struct {
            base_ptr: *const anyopaque,
            len: usize,
        };

    return struct {
        pub fn init(ptr: *const anyopaque) Iterator {
            const info = ptrInfo(ptr);
            log.debug(
                \\ info
                \\len: {d}
            , .{info.len});

            return .{
                .visitFunc = &@This().visit,
                .base_ptr = info.base_ptr,
                .len = info.len,
                .stride = stride,
            };
        }

        fn ptrInfo(ptr: *const anyopaque) PointerInfo {
            switch (type_info) {
                .array => |ar| {
                    // iter.ptr points to the array itself
                    return .{
                        .base_ptr = ptr,
                        .len = ar.len,
                    };
                },
                .pointer => |p| {
                    switch (p.size) {
                        .slice => {

                            // iter.ptr points to SLICE STRUCT, not data
                            const slice: *const T = @ptrCast(@alignCast(ptr));
                            log.debug("ptrInfo: ptr={*}, slice.ptr={*}, slice.len={d}", .{ ptr, slice.ptr, slice.len });
                            return .{
                                .base_ptr = slice.ptr,
                                .len = slice.len,
                            };
                        },
                        else => {
                            @compileError(std.fmt.comptimePrint(
                                \\ No branch for pointer of size {s}
                            , .{@tagName(ptr.size)}));
                        },
                    }
                },
                else => {
                    @compileError(std.fmt.comptimePrint(
                        \\ No branch for {s}
                    , .{@tagName(type_info)}));
                },
            }
        }

        fn visit(
            a: Allocator,
            item: *const anyopaque,
            f: *const anyopaque,
            args: *anyopaque,
        ) Error!void {
            const v: *const ItemType = @ptrCast(@alignCast(item));
            const scope = try Scope.init(v, a);
            defer scope.deinit(a);
            const func: *const fn (Scope, *anyopaque) Error!void = @ptrCast(@alignCast(f));
            try func(scope, args);
        }
    };
}
