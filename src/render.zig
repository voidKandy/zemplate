const std = @import("std");
const root = @import("root.zig");
const ast = @import("ast.zig");
const Scope = @import("Scope.zig");
const Error = root.Error;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.render);

pub fn renderStatement(
    a: Allocator,
    writer: *std.Io.Writer,
    scope: Scope,
    statement: ast.Statement,
    json_opts: std.json.Stringify.Options,
) Error!void {
    log.debug(
        \\ RENDERING STATEMENT: {s}
    , .{@tagName(statement)});
    switch (statement) {
        .@"for" => |s| {
            const ch_scope = try scope.getChildScope(a, s.access.literal);
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
                    fn render(sc: Scope, opaq_args: *anyopaque) Error!void {
                        const args: *RenderArgs = @ptrCast(@alignCast(opaq_args));
                        for (args.block.body) |st| {
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
                try iter.visit(a, n, renderFunc, &RenderArgs{
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
        .@"if" => |s| {
            _ = s;
        },
        .block => |s| {
            _ = s;
        },
        .expression => |s| {
            switch (s) {
                .access => |acc| {
                    log.debug(
                        \\WRITING ACCESS: {f}
                    , .{acc});
                    try scope.writeAccess(acc.literal, writer, json_opts, acc.json);
                },
                else => {},
            }
        },
        .literal => |s| {
            try writer.writeAll(s.content);
        },
    }
}
