const std = @import("std");
const log = std.log.scoped(.newiterate);
const comptimePrint = std.fmt.comptimePrint;
const eql = std.mem.eql;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Error = @import("root.zig").Error;

fn getVisitorFunc(T: type) !*const fn (*T, anytype) Error!void {
    if (!@hasDecl(T, "visit")) return error.MethodNotPresent;
    return @field(T, "visit");
}

pub fn StructIterationContext(VisitorCtx: type) type {
    const visitorFunc = getVisitorFunc(VisitorCtx) catch @compileError("Visitor Ctx has no public visit method");
    const NextFunc = *fn (
        *anyopaque,
    ) ?*const anyopaque;

    const VisitFunc = *fn (
        *VisitorCtx,
        *const anyopaque,
    ) Error!void;

    return struct {
        fields: std.StaticStringMap(Field),
        contexts: std.StaticStringMap(*@This()),
        arena: std.heap.ArenaAllocator,

        pub const Field = struct {
            /// pointer to type instance
            instance_ptr: usize,
            /// pointer to function that takes instance and returns next value
            next_fn_ptr: usize,
            visit_fn_ptr: usize,

            fn validateInitArgs(instance: anytype, next_func: anytype, visit_func: anytype) void {
                const instance_info = @typeInfo(@TypeOf(instance));
                validateFunctionType(visit_func, VisitFunc);
                validateFunctionType(next_func, NextFunc);

                if (!validate_instance: switch (instance_info) {
                    .pointer => break :validate_instance true,
                    else => break :validate_instance false,
                }) {
                    @compileError("instance argument must be a pointer to a instancetion");
                }
            }

            pub fn init(instance: anytype, next_func: anytype, visit_func: anytype) @This() {
                validateInitArgs(instance, next_func, visit_func);
                return .{
                    .instance_ptr = @intFromPtr(instance),
                    .next_fn_ptr = @intFromPtr(next_func),
                    .visit_fn_ptr = @intFromPtr(visit_func),
                };
            }

            pub fn next(self: @This()) ?*const anyopaque {
                return @call(.auto, @as(
                    NextFunc,
                    @ptrFromInt(self.next_fn_ptr),
                ), .{
                    @as(*anyopaque, @ptrFromInt(self.instance_ptr)),
                });
            }

            pub fn visit(self: @This(), ctx: *VisitorCtx, value: *const anyopaque) Error!void {
                return @call(
                    .auto,
                    @as(VisitFunc, @ptrFromInt(self.visit_fn_ptr)),
                    .{ ctx, value },
                );
            }
        };

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("\nVisitor Context: {s}", .{@typeName(VisitorCtx)});
            try writer.writeAll("\nFields With Iterators: \n");
            for (self.fields.keys()) |k| {
                try writer.print("{s}\n", .{k});
            }
            try writer.writeAll("\nFields With Own Contexts: \n");
            for (self.contexts.keys()) |k| {
                try writer.print(
                    \\ {s}:
                    \\ {f}
                , .{ k, self.contexts.get(k).? });
            }
        }

        pub fn init(
            comptime T: type,
            instance: anytype,
            allocator: std.mem.Allocator,
        ) Error!@This() {
            log.warn(
                \\ IterCtx.init entry
                \\ T: {s}
                \\ instance T: {s}
            , .{ @typeName(T), @typeName(@TypeOf(instance)) });
            if (@typeInfo(T) != .@"struct") {
                log.err("Could not get IterCtx for {s}", .{@typeName(T)});
                return error.InvalidType;
            }
            const info = @typeInfo(T).@"struct";
            std.debug.assert(@TypeOf(instance) == *T);
            var arena = std.heap.ArenaAllocator.init(allocator);
            const a = arena.allocator();

            var fields: std.ArrayList(struct { []const u8, Field }) = try .initCapacity(a, info.fields.len);
            var ctxs: std.ArrayList(struct { []const u8, *@This() }) = try .initCapacity(a, info.fields.len);

            inline for (info.fields) |f| {
                _ = @import("iterate.zig").validateParentAndFieldName(T, f.name) catch {
                    // BAD? maybe this validation should be moved to its own function as it should match any validation this `init` function does
                    if (@typeInfo(f.type) == .@"struct") {
                        const nested = try a.create(@This());
                        nested.* = try @This().init(f.type, &@field(instance, f.name), a);
                        try ctxs.append(a, .{ f.name, nested });
                    }
                    continue;
                };

                const I = @import("iterate.zig").StructFieldIterator(T, f.name);

                const inst = try a.create(I);
                inst.* = I.fromParentPtr(instance);

                const visitorImpl = struct {
                    fn visitWrapper(ctx: *VisitorCtx, value: *const anyopaque) Error!void {
                        const typed = @as(*const I.Item, @ptrCast(@alignCast(value)));
                        log.warn("using casted  *const {s}", .{@typeName(I.Item)});
                        return visitorFunc(ctx, typed);
                    }
                }.visitWrapper;

                const nextImpl = struct {
                    fn nextWrapper(opaq: *anyopaque) ?*const anyopaque {
                        var op: *I = @ptrCast(@alignCast(opaq));
                        const next: *const I.Item = op.next() orelse return null;
                        log.warn("Next value casted  *const {s}", .{@typeName(I.Item)});
                        return @ptrCast(next);
                    }
                }.nextWrapper;

                try fields.append(a, .{ f.name, Field.init(inst, &nextImpl, &visitorImpl) });
            }
            const fields_map_arr = try fields.toOwnedSlice(a);
            const ctxs_map_arr = try ctxs.toOwnedSlice(a);
            return .{
                .fields = try std.StaticStringMap(Field).init(fields_map_arr, a),
                .contexts = try std.StaticStringMap(*@This()).init(ctxs_map_arr, a),
                .arena = arena,
            };
        }

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            // for (self.contexts.values()) |v| {
            //     v.deinit(allocator);
            // }
            _ = allocator;
            self.fields.deinit(self.arena.allocator());
            self.contexts.deinit(self.arena.allocator());

            self.arena.deinit();
        }
    };
}

inline fn validateFunctionType(func: anytype, TargetType: type) void {
    comptime {
        const func_info = @typeInfo(@TypeOf(func));
        const expected_info = @typeInfo(TargetType);

        const f = blk: {
            if (func_info == .pointer) {
                const inner = @typeInfo(func_info.pointer.child);
                if (inner == .@"fn") {
                    break :blk inner.@"fn";
                }
            }
            @compileError("Expected func to be a function pointer. Found " ++
                @typeName(@TypeOf(func)));
        };
        const ef = @typeInfo(expected_info.pointer.child).@"fn";

        if (f.params.len != ef.params.len) {
            @compileError(comptimePrint("Expected func to have {d} parameters", .{ef.params.len}));
        }

        for (f.params[0..], ef.params[0..], 1..) |p, ep, i| {
            if (p.type != ep.type)
                @compileError(comptimePrint("Expected func's argument {d} to be of type:  {s} Found: {s}", .{
                    i,
                    @typeName(ep.type.?),
                    @typeName(p.type.?),
                }));
        }

        if (!ret: {
            const ret_info = @typeInfo(f.return_type orelse break :ret false);
            const eret_info = @typeInfo(ef.return_type orelse break :ret false);

            break :ret (std.meta.eql(eret_info, ret_info));
        }) {
            @compileError("Expected func's return type to be " ++ @typeName(ef.return_type.?) ++
                " Found " ++
                @typeName(f.return_type.?));
        }
    }
}
