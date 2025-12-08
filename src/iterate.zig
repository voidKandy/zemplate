const std = @import("std");
const log = std.log.scoped(.iterate);
const root = @import("root.zig");
const eql = std.mem.eql;
const expect = std.testing.expect;

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
