const std = @import("std");
const log = std.log.scoped(.conditional);
const eql = std.mem.eql;
const util = @import("util.zig");
const comptimePrint = std.fmt.comptimePrint;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Error = @import("root.zig").Error;

pub const ConditionalChild = struct {
    type: type,
    is_payload: bool,
};

pub inline fn UnwrapConditionalChild(comptime T: type) ?ConditionalChild {
    const info = @typeInfo(T);
    switch (info) {
        .bool, .optional => return .{ .type = T, .is_payload = info == .optional },
        else => return null,
    }
}

inline fn validateParentAndFieldName(comptime Parent: type, comptime field_name: []const u8) error{ NotConditional, ParentNotStruct, InvalidFieldName }!ConditionalChild {
    const FieldType = blk: {
        const info = @typeInfo(Parent);
        switch (info) {
            .@"struct" => {},
            else => return error.ParentNotStruct,
        }

        inline for (info.@"struct".fields) |f| {
            if (util.sliceEqualComptime(f.name, field_name))
                break :blk f.type;
        }

        return error.InvalidFieldName;
    };
    return UnwrapConditionalChild(FieldType) orelse {
        return error.NotConditional;
    };
}

pub fn StructFieldConditional(comptime Parent: type, comptime field_name: []const u8) type {
    const conditional_child = validateParentAndFieldName(Parent, field_name) catch |e|
        @compileError("Cannot make struct field conditional from " ++ @typeName(Parent) ++ "\nError: " ++ @errorName(e));

    return struct {
        instance: conditional_child.type,

        pub fn fromParentPtr(p: *Parent) @This() {
            log.debug("Creating conditional for field {s} of struct {any}", .{ field_name, Parent });
            const field: conditional_child.type = @field(p, field_name);
            return .{
                .instance = field,
            };
        }

        pub fn get(self: *@This()) ?union(enum) {
            bool: *const bool,
            payload: *const conditional_child.type,
        } {
            if (conditional_child.is_payload) return .{ .payload = &self.instance };
            // if more than bool and optionals are ever supported, this will need to change
            return .{ .bool = &self.instance };
        }
    };
}
