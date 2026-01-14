const std = @import("std");
const Scope = @import("Scope.zig");
const ast = @import("ast.zig");
const log = std.log.scoped(.Template);
const Parser = @import("Parser.zig");
const Lexer = @import("Lexer.zig");
const Error = @import("root.zig").Error;
const Allocator = std.mem.Allocator;

scope: Scope,
arena: std.heap.ArenaAllocator,
const Template = @This();

pub fn init(
    a: Allocator,
    val: anytype,
) Error!@This() {
    if (@typeInfo(@TypeOf(val)) != .pointer) @panic(
        \\ .init method expected `val` argument to be a pointer to some type
    );

    var arena = std.heap.ArenaAllocator.init(a);
    return .{
        .scope = try Scope.init(val, arena.allocator()),
        .arena = arena,
    };
}

pub fn deinit(self: *@This()) void {
    self.scope.deinit(self.arena.allocator());
    self.arena.deinit();
}

pub fn render(
    self: *@This(),
    input: []const u8,
    json_opts: std.json.Stringify.Options,
) Error![]const u8 {
    const a = self.arena.allocator();
    var w = std.Io.Writer.Allocating.init(a);

    var l: Lexer = .init(input);
    var p: Parser = try .init(a, &l);

    const program = p.parseProgram(a) catch |e| {
        p.logErrors(log);
        return e;
    };
    for (program.statements.items) |st| {
        try @import("render.zig").renderStatement(
            a,
            &w.writer,
            self.scope,
            st,
            json_opts,
        );
    }

    return try w.toOwnedSlice();
}
