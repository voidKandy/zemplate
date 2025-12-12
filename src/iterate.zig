const std = @import("std");
const log = std.log.scoped(.iterate);
const root = @import("root.zig");
const eql = std.mem.eql;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Error = @import("root.zig").Error;

pub inline fn UnwrapIterableChild(comptime T: type) ?type {
    const info = @typeInfo(T);

    return switch (info) {
        .array => |a| a.child,
        .pointer => |p| switch (p.size) {
            .slice => p.child,
            else => UnwrapIterableChild(p.child),
        },
        else => {
            if (!@inComptime())
                log.err("Cannot unwrap {s}", .{@typeName(T)});
            return null;
        },
    };
}

pub fn StructFieldIterator(comptime Parent: type, comptime field_name: []const u8) type {
    const FieldType, const FIELD_NAME = blk: {
        const info = @typeInfo(Parent);
        switch (info) {
            .@"struct" => {},
            else => @compileLog("Expected some struct type, instead got " ++ @typeName(Parent)),
        }

        inline for (info.@"struct".fields) |f| {
            if (eql(u8, f.name, field_name))
                break :blk .{ f.type, f.name };
        }
        @compileError(@typeName(Parent) ++ " Does not have field of given name");
    };

    const field_type_info = @typeInfo(FieldType);

    const ItemType = UnwrapIterableChild(FieldType) orelse @compileError(@typeName(Parent) ++ " is not iterable");

    return struct {
        instance: FieldType,
        index: usize = 0,
        pub fn fromParentPtr(p: *Parent) @This() {
            log.debug("Creating Iterator for field {s} of struct {any}", .{ FIELD_NAME, Parent });
            const field: FieldType = @field(p, FIELD_NAME);
            return .{
                .instance = field,
            };
        }

        pub fn next(self: *@This()) ?ItemType {
            defer self.index += 1;
            switch (field_type_info) {
                .array => |ar| return if (ar.len > self.index)
                    self.instance[self.index]
                else
                    null,
                .pointer => |ptr| return if (ptr.size == .slice and self.instance.len > self.index)
                    self.instance[self.index]
                else
                    null,
                else => @panic("Should be unreachable"),
            }
        }
    };
}

pub fn IterableFields(comptime T: type) type {
    const context_type_info = @typeInfo(T);
    const AMT_ITERABLE_FIELDS = blk: switch (context_type_info) {
        .@"struct" => |s| {
            var amt_cannot: usize = 0;
            inline for (s.fields) |f| {
                if (root.iterate.UnwrapIterableChild(f.type) == null) amt_cannot += 1;
            }
            break :blk s.fields.len - amt_cannot;
        },
        else => @compileError("Cannot create template from " ++ @typeName(T)),
    };

    const iterable_fields_arr: [AMT_ITERABLE_FIELDS]Type.StructField = blk: {
        var tmp: [AMT_ITERABLE_FIELDS]Type.StructField = undefined;
        var i: usize = 0;
        inline for (context_type_info.@"struct".fields) |f| {
            if (root.iterate.UnwrapIterableChild(f.type) != null) {
                tmp[i] = f;
                i += 1;
            }
        }
        break :blk tmp;
    };

    const meta_fields: struct {
        un_fields: [AMT_ITERABLE_FIELDS]Type.UnionField,
        en_fields: [AMT_ITERABLE_FIELDS]Type.EnumField,
    } = blk: {
        var ufields: [AMT_ITERABLE_FIELDS]Type.UnionField = undefined;
        var efields: [AMT_ITERABLE_FIELDS]Type.EnumField = undefined;

        inline for (iterable_fields_arr, &ufields, &efields, 0..) |iter_fld, *unfld, *enfld, j| {
            const Typ = root.iterate.UnwrapIterableChild(iter_fld.type).?;
            unfld.* = Type.UnionField{
                .alignment = @alignOf(Typ),
                .name = iter_fld.name,
                .type = Typ,
            };
            enfld.* = Type.EnumField{
                .value = j,
                .name = iter_fld.name,
            };
        }
        break :blk .{ .un_fields = ufields, .en_fields = efields };
    };

    const Tag =
        @Type(Type{
            .@"enum" = .{
                .fields = &meta_fields.en_fields,
                .tag_type = u32,
                .decls = &[_]Type.Declaration{},
                .is_exhaustive = true,
            },
        });
    const Union =
        @Type(Type{
            .@"union" = .{
                .fields = &meta_fields.un_fields,
                .decls = &[_]Type.Declaration{},
                .tag_type = Tag,
                .layout = .auto,
            },
        });

    const CreateFieldIterFunc = *const fn (std.mem.Allocator, *T) *anyopaque;
    const DestroyFieldIterFunc = *const fn (std.mem.Allocator, *anyopaque) void;
    const NextItemFunc = *const fn (*anyopaque) ?Union;
    const IterDispatch = struct {
        createFunc: CreateFieldIterFunc,
        destroyFunc: DestroyFieldIterFunc,
        nextFunc: NextItemFunc,
        current: ?Union = null,

        pub fn getNext(self: *@This(), instance: *anyopaque) bool {
            const n = self.nextFunc(instance) orelse return false;
            self.current = n;
            return true;
        }

        pub fn doWithCurrent(self: @This(), func: anytype, args: anytype) Error!void {
            switch (@typeInfo(@TypeOf(func))) {
                .@"fn" => |f| {
                    _ = f;
                    // if (f.params[1].type != @TypeOf(args)) @compileError("func argument must take args as second parameter");
                },
                else => @compileError("func argument must be a function"),
            }
            inline for (iterable_fields_arr) |f| {
                if (std.mem.eql(u8, f.name, @tagName(self.current.?))) {
                    const current = @field(self.current.?, f.name);
                    try func(current, args);
                }
            }
        }
    };

    var iterator_wrapper_arr: [AMT_ITERABLE_FIELDS]struct {
        []const u8,
        IterDispatch,
    } = undefined;

    inline for (iterable_fields_arr, &iterator_wrapper_arr) |f, *item| {
        item.*.@"0" = f.name;
        const I = root.iterate.StructFieldIterator(T, f.name);

        const createFn = struct {
            fn fromParentWrapper(a: std.mem.Allocator, parent: *T) *anyopaque {
                const instance = a.create(I) catch @panic("out of memory");
                instance.* = I.fromParentPtr(parent);
                const opaq: *anyopaque = @ptrCast(instance);
                return opaq;
            }
        }.fromParentWrapper;
        const destroyFn = struct {
            fn destroy(a: std.mem.Allocator, inst: *anyopaque) void {
                const instance: *I = @ptrCast(@alignCast(inst));
                a.destroy(instance);
            }
        }.destroy;
        const nextFn = struct {
            fn nextWrapper(inst: *anyopaque) ?Union {
                var instance: *I = @ptrCast(@alignCast(inst));
                const next = instance.next() orelse return null;
                return @unionInit(Union, f.name, next);
            }
        }.nextWrapper;
        item.@"1" = IterDispatch{
            .createFunc = createFn,
            .destroyFunc = destroyFn,
            .nextFunc = nextFn,
        };
    }

    const map = std.StaticStringMap(IterDispatch).initComptime(iterator_wrapper_arr);
    return struct {
        pub const all_iterable_struct_fields = iterable_fields_arr;
        pub const Dispatch = IterDispatch;
        pub const iter_dispatch_map = map;

        // comptime {
        //     const ChildIterators: []type = blk: {
        //         var types: [type_info.@"struct".fields.len]type = undefined;
        //         var i: usize = 0;
        //         for (type_info.@"struct".fields) |f| {
        //             const Child = IterableFields(f.type);
        //             types[i] = Child;
        //             i += 1;
        //         }
        //         break :blk types;
        //     };
        // }
    };
}
