const std = @import("std");
const root = @import("root.zig");
const iterate = @import("iterate.zig");
const util = @import("util.zig");
const ast = @import("ast.zig");
const scope_mod = @import("scope.zig");
const Error = root.Error;
const parse = root.parse;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.RenderContext);

fn getField(comptime T: type, value: *const T, name: []const u8) ?*const anyopaque {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            const f = @field(value.*, field.name);
            return @ptrCast(&f);
        }
    }

    log.warn(
        \\ Type: {s} has no field with name: '{s}'
    , .{ @typeName(T), name });
    return null;
}

const StructFieldIterator = struct {
    all: std.StringHashMap(Iterator),

    fn init(T: type, inst: T, a: Allocator, visitFn: *const fn (anytype, anytype) anyerror!void) anyerror!@This() {
        if (@typeInfo(T) != .@"struct") return error.InvalidType;
        const info = @typeInfo(T).@"struct";
        var map: std.StringHashMap(Iterator) = .init(a);

        inline for (info.fields) |f| {
            if (iterate.UnwrapIterableChild(f.type)) |ItemType| {
                const Ft = @FieldType(T, f.name);
                var field = @field(inst, f.name);
                const iter = Iterator{
                    .instance = @ptrCast(&field),
                    .visitFn = visitFn,
                    .visitWrapperFn = &struct {
                        fn wrapper(self: Iterator, o: *anyopaque, args: anytype) anyerror!void {
                            const val: ItemType = @ptrCast(o);
                            return self.visitFn(val, args);
                        }
                    }.wrapper,
                    .nextFn = &struct {
                        fn next(o: *anyopaque, i: usize) *anyopaque {
                            const val: Ft = @ptrCast(o);

                            const n: ItemType = switch (info) {
                                .array => |ar| return if (ar.len > i)
                                    &val[i]
                                else
                                    null,
                                .pointer => |ptr| return if (ptr.size == .slice and val.len > i)
                                    &val[i]
                                else
                                    null,
                                else => @panic("Should be unreachable"),
                            };

                            return @ptrCast(&n);
                        }
                    }.next,
                };
                try map.put(f.name, iter);
            }
        }

        return .{ .all = map };
    }
};

const Iterator = struct {
    instance: *anyopaque,
    index: usize = 0,
    nextFn: *const fn (*anyopaque, usize) *anyopaque,
    visitWrapperFn: *const fn (@This(), *anyopaque, anytype) anyerror!void,
    visitFn: *const fn (anytype, anytype) anyerror!void,

    fn next(self: *@This()) *anyopaque {
        defer self.index += 1;
        return self.nextFn(self.instance, self.index);
    }

    pub fn callNextAndVisit(self: *@This(), args: anytype) anyerror!void {
        const n = self.next();
        return self.visitWrapperFn(n, args);
    }
};

fn genericRenderVisit(n: anytype, args: anytype) anyerror!void {
    const a: struct { *std.Io.Writer } = @ptrCast(args);
    try a.@"0".print("{f}", .{n});
    return;
}

/// Can be called on any pointer to a struct
/// or a pointer to that (recursively)
/// SHOULD RETURN AN OBJECT
fn accessFieldOfStructOrPtr(
    access: ast.AccessExpression,
    stmt: ast.Statement,
    writer: *std.Io.Writer,
    val: anytype,
    json_opts: std.json.Stringify.Options,
) Error!void {
    switch (@typeInfo(@TypeOf(val))) {
        .@"struct" => {
            // const memo: scope_mod.Scope(@TypeOf(val)) = .init();
            // var v = val;
            // const func = memo.access_map.get(access.literal) orelse {
            //     log.err("failed to get function for key: {s}", .{access.literal});
            //     return error.CannotIterate;
            // };
            // try func(writer, @ptrCast(&v), stmt, json_opts);
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .@"struct" => try accessFieldOfStructOrPtr(access, stmt, writer, val.*, json_opts),
                .pointer => try accessFieldOfStructOrPtr(access, stmt, writer, val.*.*, json_opts),
                else => @panic("unexpected"),
            }
            switch (ptr.size) {
                .many, .slice => {
                    var i = 0;
                    if (ptr.sentinel()) |sent| {
                        while (!std.meta.eql(val[i], sent)) : (i += 1)
                            try accessFieldOfStructOrPtr(access, stmt, writer, val[i], json_opts);
                    } else return error.CannotSerialize;
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn renderStatement(
    a: Allocator,
    writer: *std.Io.Writer,
    scope: scope_mod.Scope,
    statement: ast.Statement,
    json_opts: std.json.Stringify.Options,
) Error!void {
    log.warn(
        \\ RENDERING STATEMENT: {s}
    , .{@tagName(statement)});
    // _ = writer;
    // _ = val;
    switch (statement) {
        .@"for" => |s| {
            const getChScopeFn = scope.child_scopes.get(s.access.literal) orelse {
                log.err("No scope for literal: {s}", .{s.access.literal});
                // BAD wrong error name
                // REDO YOUR ERRORS BUDDY
                return error.CannotIterate;
            };
            const ch_scope = try getChScopeFn(a, scope);
            defer ch_scope.deinit(a);

            var iter = try ch_scope.createIterator();

            const RenderArgs =
                struct {
                    a: Allocator,
                    writer: *std.Io.Writer,
                    block: ast.BlockStatement,
                    json_opts: std.json.Stringify.Options,
                };
            const renderFunc =
                &struct {
                    fn render(sc: scope_mod.Scope, opaq_args: *anyopaque) Error!void {
                        const args: *RenderArgs = @ptrCast(@alignCast(opaq_args));
                        for (args.block.body) |st| {
                            log.warn(
                                \\RENDERING {s}
                            , .{@tagName(st)});
                            try renderStatement(
                                args.a,
                                args.writer,
                                sc,
                                st,
                                args.json_opts,
                            );
                        }
                    }
                }.render;

            while (iter.next()) |n| {
                log.warn(
                    \\got next 
                , .{});

                try iter.visit(a, n, renderFunc, &RenderArgs{
                    .a = a,
                    .writer = writer,
                    .block = s.block,
                    .json_opts = json_opts,
                });
                log.warn("finished visit", .{});
            }
            log.warn("out", .{});

            if (s.alternatives) |alts| {
                for (alts) |alt| {
                    if (alt.condition) |cond| {
                        _ = cond;
                    }
                }
            }
        },
        .@"if" => |s| {
            _ = s;
        },
        .block => |s| {
            _ = s;
        },
        .expression => |s| {
            switch (s) {
                .access => |acc| {
                    const writeFn = scope.access_map.get(acc.literal) orelse {
                        log.err("No scope for literal: {s}", .{acc.literal});
                        return error.CannotSerialize;
                    };
                    try writeFn(writer, scope, json_opts, acc.json);
                },
                else => {},
            }
        },
        .literal => |s| {
            try writer.writeAll(s.content);
        },
    }
}
