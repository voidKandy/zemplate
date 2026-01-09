const std = @import("std");
const ast = @import("ast.zig");
const root = @import("root.zig");
const util = @import("util.zig");
const log = std.log.scoped(.scope);
const renderStatement = @import("render_context.zig").renderStatement;
const Error = root.Error;

/// used to actually enter a scope
pub inline fn ScopeLookup(comptime T: type) type {
    return struct {
        pub fn get(
            name: []const u8,
            inst: anytype,
        ) RuntimeScope {
            if (@TypeOf(inst) != T) @panic("Wrong type passed to .get");
            if (std.mem.allEqual(u8, name, '.')) {
                const depth = std.mem.count(u8, name, ".");
                if (depth > 1) @panic("UNIMPLEMENTED"); // dont have a way to handle outer scopes yet
                const S = Scope(T) catch @panic("HANDLE GRACEFULLY");
                return .{
                    .map = S.init().access_map,
                    .base = @ptrCast(&inst),
                };
            }
            inline for (@typeInfo(T).@"struct".fields) |fd| {
                if (util.sliceEqualComptime(u8, fd, name)) {
                    const S = Scope(fd.type) catch @panic("HANDLE GRACEFULLY");
                    return .{
                        .map = S.init().access_map,
                        .base = @ptrCast(@field(inst, fd.name)),
                    };
                }
            }
        }
    };
}

fn DerefStruct(comptime T: type) error{NotStructType}!type {
    switch (@typeInfo(T)) {
        .@"struct" => return T,
        .pointer => |ptr| return DerefStruct(ptr.child),
        else => {
            // @compileLog(std.fmt.comptimePrint(
            //     \\ Cannot Deref type '{s}' as struct
            // , .{@typeName(T)}));

            return error.NotStructType;
        },
    }
}

/// should match the signature of renderStatement
/// except anytype -> *anyopaque
const ScopeFunc = *const fn (
    *std.Io.Writer,
    *anyopaque,
    ast.Statement,
    std.json.Stringify.Options,
) Error!void;

inline fn accessMapKvs(comptime T: type) []const struct { []const u8, ScopeFunc } {
    const FIELDS = @typeInfo(T).@"struct".fields;

    const N_NESTED = blk: {
        comptime var i: usize = 0;
        inline for (FIELDS) |f| {
            switch (@typeInfo(f.type)) {
                .@"struct" => |st| i += st.fields.len,
                else => {},
            }
        }
        break :blk i;
    };

    const MAP_SIZE = FIELDS.len + N_NESTED;

    const CallFunc = struct {
        fn getFunc(
            comptime Type: type,
            comptime field_name: []const u8,
        ) ScopeFunc {
            return &struct {
                fn call(
                    w: *std.Io.Writer,
                    o: *anyopaque,
                    st: ast.Statement,
                    json_opts: std.json.Stringify.Options,
                ) Error!void {
                    const val: *Type = @ptrCast(@alignCast(o));
                    const fld = @field(val, field_name);
                    try renderStatement(w, fld, st, json_opts);
                }
            }.call;
        }
    };

    const arr: [MAP_SIZE]struct { []const u8, ScopeFunc } = blk: {
        var tmp: [MAP_SIZE]struct { []const u8, ScopeFunc } = undefined;
        var i: usize = 0;
        inline for (FIELDS) |f| {
            tmp[i] = .{
                std.fmt.comptimePrint(".{s}", .{f.name}),
                CallFunc.getFunc(T, f.name),
            };
            i += 1;

            switch (@typeInfo(f.type)) {
                .@"struct" => |st| {
                    inline for (st.fields) |fld| {
                        tmp[i] = .{
                            std.fmt.comptimePrint(".{s}.{s}", .{ f.name, fld.name }),
                            CallFunc.getFunc(f.type, fld.name),
                        };

                        i += 1;
                    }
                },
                else => {},
            }
        }
        break :blk tmp;
    };

    return &arr;
}

pub const RuntimeScope = struct {
    base: *anyopaque,
    map: *const std.StaticStringMap(ScopeFunc),
};

pub inline fn Scope(comptime T: type) error{NotStructType}!type {
    // pub inline fn Scope(comptime T: type) type {
    const DerefT = try DerefStruct(T);
    return struct {
        access_map: std.StaticStringMap(ScopeFunc) = .initComptime(accessMapKvs(DerefT)),

        pub fn init() @This() {
            const self = @This(){};
            log.warn(
                \\SCOPE FOR {s} INIT
            , .{@typeName(DerefT)});
            for (self.access_map.keys()) |k| {
                log.warn(
                    \\ K: {s}
                , .{k});
            }
            return self;
        }
    };
}
