const std = @import("std");
const root = @import("root.zig");
const ast = @import("ast.zig");
const scope_mod = @import("scope.zig");
const Error = root.Error;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.render);

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
