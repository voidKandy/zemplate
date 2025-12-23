const std = @import("std");
const log = std.log.scoped(.iterate);
const eql = std.mem.eql;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Error = @import("root.zig").Error;

pub inline fn UnwrapIterableChild(comptime T: type) ?type {
    const info = @typeInfo(T);
    const child_opt: ?type = blk: {
        switch (info) {
            .array => |a| break :blk a.child,
            .pointer => |p| switch (p.size) {
                .slice => break :blk p.child,
                else => break :blk UnwrapIterableChild(p.child),
            },
            // .@"struct" => |s| {
            //     // array list check
            //     if (s.fields.len == 2 and eql(u8, s.fields[0].name, "items") and eql(u8, s.fields[1].name, "capacity")) {
            //         break :blk @typeInfo(s.fields[0].type).pointer.child;
            //     }
            // },
            else => {},
        }
        break :blk null;
    };
    return child_opt;
}

pub fn StructFieldIterator(comptime Parent: type, comptime field_name: []const u8) error{ NotIterable, ParentNotStruct, InvalidFieldName }!type {
    const FieldType = blk: {
        const info = @typeInfo(Parent);
        switch (info) {
            .@"struct" => {},
            else => return error.ParentNotStruct,
        }

        inline for (info.@"struct".fields) |f| {
            if (eql(u8, f.name, field_name))
                break :blk f.type;
        }

        return error.InvalidFieldName;
    };

    const field_type_info = @typeInfo(FieldType);

    const ItemType = UnwrapIterableChild(FieldType) orelse {
        return error.NotIterable;
    };

    return struct {
        instance: FieldType,
        index: usize = 0,
        pub const Item = ItemType;

        pub fn fromParentPtr(p: *Parent) @This() {
            log.debug("Creating Iterator for field {s} of struct {any}", .{ field_name, Parent });
            const field: FieldType = @field(p, field_name);
            return .{
                .instance = field,
            };
        }

        pub fn next(self: *@This()) ?*const ItemType {
            defer self.index += 1;
            switch (field_type_info) {
                .array => |ar| return if (ar.len > self.index)
                    &self.instance[self.index]
                else
                    null,
                .pointer => |ptr| return if (ptr.size == .slice and self.instance.len > self.index)
                    &self.instance[self.index]
                else
                    null,
                else => @panic("Should be unreachable"),
            }
        }
    };
}

inline fn getAmtIterableFields(comptime T: type) usize {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            var amt_cannot: usize = 0;
            inline for (s.fields) |f| {
                if (UnwrapIterableChild(f.type) == null) amt_cannot += 1;
            }
            return s.fields.len - amt_cannot;
        },
        else => return 0,
    }
}

const Field = struct {
    name: []const u8,
    type: type,
    // parent: type,

    fn fromStructField(f: Type.StructField) @This() {
        return .{ .name = f.name, .type = f.type };
    }
    fn fromFieldWithParentFieldName(field: @This(), parent_field_name: []const u8) @This() {
        const name = std.fmt.comptimePrint("{s}.{s}", .{ parent_field_name, field.name });
        return .{ .name = name, .type = field.type };
    }

    fn nameInfo(self: @This()) struct {
        parent_name: ?[]const u8,
        field_name: []const u8,
    } {
        var iter = std.mem.splitBackwardsScalar(u8, self.name, '.');
        const field_name = iter.first();
        const parent_name =
            if (iter.next()) |n| n else null;
        return .{ .field_name = field_name, .parent_name = parent_name };
    }
};

pub fn IterableFields(comptime Context: type) type {
    const context_type_info = @typeInfo(Context);
    switch (context_type_info) {
        .@"struct" => {},
        else => @compileError("Cannot get iterable fields of non struct type: " ++ @typeName(Context)),
    }

    const PARENT_UNION_OUTERMOST_TAG_NAME = @typeName(Context);
    const AMT_ITERABLE_FIELDS = getAmtIterableFields(Context);
    const AMT_CHILDREN_WITH_ITERABLE_FIELDS = blk: {
        var n = 0;
        inline for (context_type_info.@"struct".fields) |f| {
            if (getAmtIterableFields(f.type) > 0)
                n += 1;
        }
        break :blk n;
    };

    const CHILDREN_DATA: struct {
        /// flattened total amount of fields;
        /// the sum of all iterable fields per child
        total_fields: usize,
        map: std.StaticStringMap(Field),

        inline fn get() @This() {
            var amt: usize = 0;
            var len: usize = 0;
            var tmp: [AMT_CHILDREN_WITH_ITERABLE_FIELDS]struct { []const u8, Field } = undefined;
            inline for (context_type_info.@"struct".fields) |f| {
                const n = getAmtIterableFields(f.type);
                amt += n;
                if (n > 0) {
                    tmp[len] = .{ f.name, Field.fromStructField(f) };
                    len += 1;
                }
            }
            const arr = tmp[0..len];
            return .{
                .total_fields = amt,
                .map = std.StaticStringMap(Field).initComptime(arr),
            };
        }
    } = .get();

    const TOTAL_ITERABLE_FIELDS = CHILDREN_DATA.total_fields + AMT_ITERABLE_FIELDS;

    const ITERABLE_FIELDS_DATA: struct {
        /// Flattened list of all Fields that need to have an entry in the outermost 'map'
        /// Fields of the outermost `T` are added if they are, in fact iterable
        /// Fields of inner fields that have iterable fields are also added
        all_fields: [TOTAL_ITERABLE_FIELDS]Field = undefined,
        /// The indices at which the parent `T` of the flattened fields are stored here
        change_indices: [AMT_CHILDREN_WITH_ITERABLE_FIELDS]usize = undefined,

        inline fn get() @This() {
            var all_fields: [TOTAL_ITERABLE_FIELDS]Field = undefined;
            var change_indices: [AMT_CHILDREN_WITH_ITERABLE_FIELDS]usize = undefined;

            var i: usize = 0;
            inline for (context_type_info.@"struct".fields) |f| {
                if (UnwrapIterableChild(f.type) != null) {
                    all_fields[i] = Field.fromStructField(f);
                    i += 1;
                }
            }
            const children_fields = CHILDREN_DATA.map.values();
            if (children_fields.len != AMT_CHILDREN_WITH_ITERABLE_FIELDS)
                @compileError("Children fields length does not equal AMT_CHILDREN_WITH_ITERABLE_FIELDS");

            for (0..AMT_CHILDREN_WITH_ITERABLE_FIELDS) |j| {
                const field = children_fields[j];
                change_indices[j] = i;
                for (IterableFields(field.type).all_iterable_struct_fields) |f| {
                    all_fields[i] = Field.fromFieldWithParentFieldName(f, field.name);
                    i += 1;
                }
            }

            return .{
                .all_fields = all_fields,
                .change_indices = change_indices,
            };
        }
    } = .get();

    const ReturnUnionCreationData = struct {
        un_fields: [TOTAL_ITERABLE_FIELDS]Type.UnionField = undefined,
        en_fields: [TOTAL_ITERABLE_FIELDS]Type.EnumField = undefined,
    };

    const ParentUnionCreationData = struct {
        un_fields: [AMT_CHILDREN_WITH_ITERABLE_FIELDS + 1]Type.UnionField = undefined,
        en_fields: [AMT_CHILDREN_WITH_ITERABLE_FIELDS + 1]Type.EnumField = undefined,
    };

    const UNION_CREATION_DATA: struct {
        return_union: ReturnUnionCreationData,
        parent_union: ParentUnionCreationData,

        inline fn get() @This() {
            var return_union_dat = ReturnUnionCreationData{};
            var parent_union_dat = ParentUnionCreationData{};

            inline for (ITERABLE_FIELDS_DATA.all_fields, 0..) |iter_fld, i| {
                const Typ = UnwrapIterableChild(iter_fld.type).?;
                const name = iter_fld.name[0..iter_fld.name.len :0];
                return_union_dat.un_fields[i] =
                    Type.UnionField{
                        .alignment = @alignOf(Typ),
                        .name = name,
                        .type = Typ,
                    };
                return_union_dat.en_fields[i] =
                    Type.EnumField{
                        .value = i,
                        .name = name,
                    };
            }

            parent_union_dat.un_fields[0] =
                Type.UnionField{
                    .alignment = @alignOf(Context),
                    .name = PARENT_UNION_OUTERMOST_TAG_NAME,
                    .type = Context,
                };
            parent_union_dat.en_fields[0] =
                Type.EnumField{
                    .value = 0,
                    .name = PARENT_UNION_OUTERMOST_TAG_NAME,
                };
            inline for (CHILDREN_DATA.map.values(), 1..) |v, i| {
                const name = v.name[0.. :0];
                parent_union_dat.un_fields[i] =
                    Type.UnionField{
                        .alignment = @alignOf(v.type),
                        .name = name,
                        .type = v.type,
                    };
                parent_union_dat.en_fields[i] =
                    Type.EnumField{
                        .value = i,
                        .name = name,
                    };
            }
            return .{ .return_union = return_union_dat, .parent_union = parent_union_dat };
        }
    } = .get();

    const ReturnTag =
        @Type(Type{
            .@"enum" = .{
                .fields = &UNION_CREATION_DATA.return_union.en_fields,
                .tag_type = u32,
                .decls = &[_]Type.Declaration{},
                .is_exhaustive = true,
            },
        });
    const ReturnUnion =
        @Type(Type{
            .@"union" = .{
                .fields = &UNION_CREATION_DATA.return_union.un_fields,
                .decls = &[_]Type.Declaration{},
                .tag_type = ReturnTag,
                .layout = .auto,
            },
        });

    const ParentTag =
        @Type(Type{
            .@"enum" = .{
                .fields = &UNION_CREATION_DATA.parent_union.en_fields,
                .tag_type = u32,
                .decls = &[_]Type.Declaration{},
                .is_exhaustive = true,
            },
        });

    const ParentUnion =
        @Type(Type{
            .@"union" = .{
                .fields = &UNION_CREATION_DATA.parent_union.un_fields,
                .decls = &[_]Type.Declaration{},
                .tag_type = ParentTag,
                .layout = .auto,
            },
        });

    const CreateFieldIterFunc = *const fn (std.mem.Allocator, *ParentUnion) *anyopaque;
    const DestroyFieldIterFunc = *const fn (std.mem.Allocator, *anyopaque) void;
    const NextItemFunc = *const fn (*anyopaque) ?ReturnUnion;
    const IterDispatch = struct {
        createFunc: CreateFieldIterFunc,
        destroyFunc: DestroyFieldIterFunc,
        nextFunc: NextItemFunc,
        current: ?ReturnUnion = null,

        pub fn getNext(self: *@This(), instance: *anyopaque) bool {
            const n = self.nextFunc(instance) orelse {
                self.current = null;
                return false;
            };
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
            inline for (ITERABLE_FIELDS_DATA.all_fields) |f| {
                if (std.mem.eql(u8, f.name, @tagName(self.current.?))) {
                    const current = @field(self.current.?, f.name);
                    try func(current, args);
                }
            }
        }
    };

    var iterator_wrapper_arr: [TOTAL_ITERABLE_FIELDS]struct {
        []const u8,
        IterDispatch,
    } = undefined;

    var next_change_index: ?usize = if (ITERABLE_FIELDS_DATA.change_indices.len > 0) ITERABLE_FIELDS_DATA.change_indices[0] else null;
    var current_parent: ParentTag = @enumFromInt(0);
    inline for (ITERABLE_FIELDS_DATA.all_fields, &iterator_wrapper_arr, 0..) |f, *item, i| {
        if (next_change_index != null and next_change_index.? == i) {
            const index = @intFromEnum(current_parent) + 1;
            current_parent = @enumFromInt(index);
            next_change_index = if (ITERABLE_FIELDS_DATA.change_indices.len > index) ITERABLE_FIELDS_DATA.change_indices[index] else null;
        }
        const name_info = f.nameInfo();
        const parent_name = @tagName(current_parent);

        if (name_info.parent_name) |n|
            if (!eql(u8, n, parent_name)) @compileError("Expected " ++ n ++ " and " ++ parent_name ++ " to be the same");

        const ParentType = @FieldType(ParentUnion, parent_name);

        item.*.@"0" = f.name;

        const I = StructFieldIterator(ParentType, name_info.field_name);

        const createFn = struct {
            fn fromParentWrapper(a: std.mem.Allocator, parent_u: *ParentUnion) *anyopaque {
                var parent = @field(parent_u, parent_name);
                const instance = a.create(I) catch @panic("out of memory");
                instance.* = I.fromParentPtr(&parent);
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
            fn nextWrapper(inst: *anyopaque) ?ReturnUnion {
                var instance: *I = @ptrCast(@alignCast(inst));
                const next = instance.next() orelse return null;
                return @unionInit(ReturnUnion, f.name, next);
            }
        }.nextWrapper;
        item.@"1" = IterDispatch{
            .createFunc = createFn,
            .destroyFunc = destroyFn,
            .nextFunc = nextFn,
        };
    }

    if (iterator_wrapper_arr.len == 0) {
        @compileError("iterator_wrapper_arr is empty");
    }

    for (iterator_wrapper_arr) |e| {
        if (e.@"0".len == 0) {
            @compileError("empty key in StaticStringMap");
        }
    }

    const map = std.StaticStringMap(IterDispatch).initComptime(iterator_wrapper_arr);
    return struct {
        pub const all_iterable_struct_fields = ITERABLE_FIELDS_DATA.all_fields;
        pub const Dispatch = IterDispatch;
        pub const PUnion = ParentUnion;
        pub const PTag = ParentTag;
        pub const iter_dispatch_map = map;
        pub const AMT_TAG_VARIANTS: usize = std.meta.fields(PTag).len;

        pub fn initParentUnion(tag: PTag, context: Context) PUnion {
            const is_top_level_access = @intFromEnum(tag) == 0;

            inline for (@typeInfo(PUnion).@"union".fields) |uf| {
                if (eql(u8, @tagName(tag), uf.name)) {
                    if (is_top_level_access) {
                        return @unionInit(PUnion, PARENT_UNION_OUTERMOST_TAG_NAME, context);
                    } else {
                        inline for (context_type_info.@"struct".fields) |sf| {
                            if (sliceEqualComptime(sf.name, uf.name)) {
                                return @unionInit(PUnion, uf.name, @field(context, sf.name));
                            }
                        }
                    }
                }
            }
            @panic("could not init union for tag");
        }
    };
}

/// using std.mem.eql on two comptime strings can sometimes return false positives
inline fn sliceEqualComptime(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    inline for (a, 0..) |c, i| {
        if (c != b[i]) return false;
    }
    return true;
}
