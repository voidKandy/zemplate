const std = @import("std");
const root = @import("root.zig");
const iterate = @import("iterate.zig");
const util = @import("util.zig");
const ast = @import("ast.zig");
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

pub fn renderStatement(
    a: Allocator,
    writer: *std.Io.Writer,
    val: anytype,
    statement: ast.Statement,
    json_opts: std.json.Stringify.Options,
) anyerror!void {
    // _ = writer;
    // _ = val;
    switch (statement) {
        .@"for" => |s| {
            for (s.block.body) |b| {
                try renderStatement(a, writer, val, b, json_opts);
            }
            if (s.alternatives) |alts| {
                for (alts) |alt| {
                    if (alt.condition) |cond| {
                        _ = cond;
                    }
                }
            }
            // const this_iter = iter.all.get(s.access[1..]) orelse @panic("NO ITER");
            // this_iter.callNextAndVisit(.{writer});
        },
        .@"if" => |s| {
            _ = s;
        },
        .block => |s| {
            _ = s;
        },
        .expression => |s| {
            if (s.access.literal.len == 1 and s.access.literal[0] == '.') {
                try util.writeType(
                    @TypeOf(val),
                    val,
                    writer,
                    json_opts,
                    s.access.json,
                );
            } else {
                try util.writeField(
                    val,
                    writer,
                    s.access.literal[1..],
                    json_opts,
                    s.access.json,
                );
            }
        },
        .literal => |s| {
            _ = s;
        },
    }
}

/// eventually generalize to Scope
/// should include Iteration context as well as conditional Context
const IterationScope = struct {
    const IterCtx = @import("iterate.zig").StructIterationContext(@This());

    arena: std.heap.ArenaAllocator,
    writer: std.Io.Writer.Allocating,
    /// In order to own the lifetimes of this we need to store it here
    /// it may look unused but do not remove!
    iter_ctx: IterCtx,
    /// The name of the actual field being accessed
    iterated_field_name: []const u8,
    iterated_field: IterCtx.Field,

    statement: ast.Statement,
    json_opts: std.json.Stringify.Options,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = self;
        try writer.print(
            \\ Unimplemented
        , .{});
    }

    pub fn init(
        OuterType: type,
        outer: anytype,
        a: Allocator,
        iterated_field_name: []const u8,
        statement: ast.Statement,
        json_opts: std.json.Stringify.Options,
    ) Error!@This() {
        if (@TypeOf(outer) != *OuterType) @compileError(std.fmt.comptimePrint(
            \\ Expected types to match
            \\ {s} != *{s}
        , .{ @typeName(@TypeOf(outer)), @typeName(OuterType) }));

        var iter_ctx = try IterCtx.init(OuterType, outer, a);
        log.debug("Created iteration context: \n{f}\n", .{iter_ctx});
        const field = iter_ctx.getField(iterated_field_name) orelse return error.CannotIterate;
        const arena = std.heap.ArenaAllocator.init(a);
        const writer: std.Io.Writer.Allocating = .init(a);
        return @This(){
            .arena = arena,
            .writer = writer,
            .iter_ctx = iter_ctx,
            .iterated_field_name = iterated_field_name,
            .iterated_field = field,
            .statement = statement,
            .json_opts = json_opts,
        };
    }

    pub fn deinit(self: *@This(), a: Allocator) void {
        self.arena.deinit();
        self.writer.deinit();
        self.iter_ctx.deinit(a);
    }

    fn writeAccess(
        self: @This(),
        v: anytype,
        fieldname_check: []const u8,
        print_json: bool,
    ) anyerror!void {
        switch (@typeInfo(@TypeOf(v))) {
            .@"struct" => |s| {
                inline for (s.fields) |f| {
                    if (std.mem.eql(u8, f.name, fieldname_check)) {
                        util.writeField(
                            v,
                            self.writer,
                            fieldname_check,
                            self.fjson_opts,
                            self.print_json,
                        ) catch |e| {
                            log.err(
                                \\ Failed to writefield: {any}
                            , .{e});
                            return e;
                        };
                    }
                }
            },

            .pointer => |ptr| {
                if (ptr.size != .one) return;

                try self.writeAccess(
                    fieldname_check,
                    v,
                    self.writer,
                    self.json_opts,
                    print_json,
                );
            },
            else => {},
        }
    }

    /// This function is what handles a "next iteration" of some field of the parent struct
    pub fn visit(self: *@This(), val: anytype) Error!void {
        switch (self.statement) {
            .@"if" => {},
            .@"for" => |_| {},
            .block => {},
            .expression => |e| {
                switch (e) {
                    .access => |acc| {
                        try self.writeAccess(
                            val,
                            acc.literal,
                            acc.json,
                        );
                    },
                    .comparison => {},
                    .literal => {},
                }
            },
        }

        // var in_expression = false;

        // var tok = self.statement.nextToken();
        // while (tok.typ != .eof) : (tok = self.statement.nextToken()) {
        //     visit_log.debug(
        //         \\On token: {any}
        //     , .{tok.typ});
        //     switch (tok.typ) {}
        //     if (!tok.typ.isWhitespace()) self.prev_token = tok.typ;
        // }
    }
};
