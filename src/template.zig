const std = @import("std");
const Scope = @import("Scope.zig");
const ast = @import("ast.zig");
const log = std.log.scoped(.template);
const Parser = @import("Parser.zig");
const Lexer = @import("Lexer.zig");
const Error = @import("root.zig").Error;
const Allocator = std.mem.Allocator;

pub fn Template(comptime T: type) type {
    return struct {
        ptr: *T,
        allocator: Allocator,
        render_arena: std.heap.ArenaAllocator,

        const Self = @This();

        pub fn init(
            a: Allocator,
            val: T,
        ) Error!@This() {
            const ptr = try a.create(T);
            ptr.* = val;
            return .{
                .ptr = ptr,
                .allocator = a,
                .render_arena = std.heap.ArenaAllocator.init(a),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.render_arena.deinit();
            self.allocator.destroy(self.ptr);
        }

        pub fn render(
            self: *@This(),
            input: []const u8,
            json_opts: std.json.Stringify.Options,
        ) Error![]const u8 {
            const render_allocator = self.render_arena.allocator();
            var w = std.Io.Writer.Allocating.init(render_allocator);

            var l: Lexer = .init(input);
            var p: Parser = try .init(render_allocator, &l);
            const scope = try Scope.init(self.ptr, render_allocator);

            const program = p.parseProgram(render_allocator) catch |e| {
                p.logErrors(log);
                return e;
            };
            for (program.statements.items) |st| {
                try @import("render.zig").renderStatement(
                    render_allocator,
                    &w.writer,
                    scope,
                    st,
                    json_opts,
                );
            }

            return try w.toOwnedSlice();
        }
    };
}
