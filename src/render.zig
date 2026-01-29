const std = @import("std");
const root = @import("root.zig");
const util = @import("util.zig");
const ast = @import("ast.zig");
const Scope = @import("Scope.zig");
const Error = root.Error;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.render);

const RenderArgs = struct {
    parent_scope: ?*const Scope,
    a: Allocator,
    writer: *std.Io.Writer,
    block: ast.BlockStatement,
    json_opts: std.json.Stringify.Options,
};

fn visitorRender(sc: Scope, opaq_args: *anyopaque) Error!void {
    const args: *RenderArgs = @ptrCast(@alignCast(opaq_args));
    var s = sc;
    s.parent = args.parent_scope;
    for (args.block.body) |st|
        try renderStatement(
            args.a,
            args.writer,
            s,
            st,
            args.json_opts,
        );
}

const ScopeList = struct {
    all: std.SinglyLinkedList = .{},

    const Node = struct {
        node: std.SinglyLinkedList.Node,
        scope: Scope,
    };

    pub fn prepend(self: *@This(), a: Allocator, scope: Scope) error{OutOfMemory}!void {
        const scope_ptr = try a.create(Scope);
        scope_ptr.* = scope;
        self.all.prepend(scope_ptr);
    }
};

fn renderIfStmtOrElseBlk(
    a: Allocator,
    writer: *std.Io.Writer,
    scope: Scope,
    if_or_else: union(enum) { @"if": ast.IfStatement, @"else": ast.ElseBlock },
    json_opts: std.json.Stringify.Options,
) Error!void {
    const alternatives = switch (if_or_else) {
        .@"if" => |i| i.alternatives,
        else => null,
    };

    const Cond = union(enum) {
        value: bool,
        access: []const u8,
    };

    const condition: ?Cond = blk: {
        break :blk switch (switch (if_or_else) {
            .@"if" => |i| i.condition,
            .@"else" => |e| if (e.condition) |cond| cond else break :blk null,
        }) {
            .literal => |lit| switch (lit.*) {
                .boolean => |b| Cond{ .value = b },
                .string => |str| Cond{ .value = str.len != 0 },
                .integer => |num| Cond{ .value = num != 0 },
            },
            .access => |acc| Cond{ .access = acc.literal },
            .comparison => |cmp| Cond{ .value = try scope.evalComparison(a, cmp.left, cmp.right) },
        };
    };

    const block = switch (if_or_else) {
        .@"if" => |i| i.block,
        .@"else" => |e| e.block,
    };

    if (condition) |c| {
        switch (c) {
            .value => |value| {
                if (value)
                    for (block.body) |stmt|
                        try renderStatement(a, writer, scope, stmt, json_opts);
            },
            .access => |acc| {
                const period_prefix = util.countPeriodsPrefix(acc);
                const scope_is_root = period_prefix == 1 and acc.len == 1;

                const if_scope: Scope =
                    if (scope_is_root)
                        scope
                    else if (period_prefix > 1)
                        try (try scope.getParentScope(period_prefix)).getChildScope(a, acc[period_prefix - 1 ..])
                    else
                        try scope.getChildScope(a, acc);

                defer if (!scope_is_root and period_prefix != 1) if_scope.deinit(a);

                var cond = try if_scope.createConditional();
                const get_result = cond.get();

                try cond.visit(a, get_result, &visitorRender, &RenderArgs{
                    .parent_scope = &if_scope,
                    .a = a,
                    .writer = writer,
                    .block = block,
                    .json_opts = json_opts,
                });
            },
        }
    }

    if (alternatives) |alts|
        for (alts) |alt|
            try renderIfStmtOrElseBlk(a, writer, scope, .{ .@"else" = alt }, json_opts);
}

pub fn renderStatement(
    a: Allocator,
    writer: *std.Io.Writer,
    scope: Scope,
    statement: ast.Statement,
    json_opts: std.json.Stringify.Options,
) Error!void {
    log.debug(
        \\ RENDERING STATEMENT: {s}
        \\ SCOPE: {f}
    , .{ @tagName(statement), scope });
    switch (statement) {
        .@"for" => |s| {
            const period_prefix = util.countPeriodsPrefix(s.access.literal);
            const scope_is_root = period_prefix == 1 and s.access.literal.len == 1;

            const for_scope: Scope =
                if (scope_is_root)
                    scope
                else if (period_prefix > 1)
                    try (try scope.getParentScope(period_prefix)).getChildScope(a, s.access.literal[period_prefix - 1 ..])
                else
                    try scope.getChildScope(a, s.access.literal);

            defer if (!scope_is_root and period_prefix != 1) for_scope.deinit(a);

            var iter = try for_scope.createIterator();

            while (iter.next()) |n| {
                try iter.visit(a, n, &visitorRender, &RenderArgs{
                    .parent_scope = &for_scope,
                    .a = a,
                    .writer = writer,
                    .block = s.block,
                    .json_opts = json_opts,
                });
            }

            if (s.alternatives) |alts| {
                for (alts) |alt| {
                    if (alt.condition) |cond| {
                        _ = cond;
                    }
                }
            }
        },
        .@"if" => |s| try renderIfStmtOrElseBlk(a, writer, scope, .{ .@"if" = s }, json_opts),
        .block => |s| {
            _ = s;
        },
        .expression => |s| {
            switch (s) {
                .access => |acc| {
                    const sc, const lookup = try scope.getScopeAndAccess(acc.literal);
                    try sc.*.writeAccess(lookup, writer, json_opts, acc.json);
                },
                else => {},
            }
        },
        .literal => |s| {
            try writer.writeAll(s.content);
        },
    }
}
