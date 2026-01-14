const std = @import("std");
const Scope = @import("Scope.zig");
const ast = @import("ast.zig");
const log = std.log.scoped(.Template);
const Parser = @import("Parser.zig");
const Lexer = @import("Lexer.zig");
const Error = @import("root.zig").Error;
const Allocator = std.mem.Allocator;

scope: Scope,
program: ast.Program,
/// ast.Statements depend on the lifetime of Parser
parser: Parser,
allocator: Allocator,
json_opts: std.json.Stringify.Options,

const Template = @This();

pub fn init(
    a: Allocator,
    val: anytype,
    input: []const u8,
    json_opts: ?std.json.Stringify.Options,
) Error!@This() {
    if (@typeInfo(@TypeOf(val)) != .pointer) @panic(
        \\ .init method expected `val` argument to be a pointer to some type
    );

    var l: Lexer = .init(input);
    var p: Parser = try .init(a, &l);

    return .{
        .program = p.parseProgram(a) catch |e| {
            p.logErrors(log);
            return e;
        },
        .parser = p,
        .scope = try Scope.init(val, a),
        .allocator = a,
        .json_opts = json_opts orelse .{},
    };
}

pub fn deinit(self: *@This()) void {
    self.program.statements.deinit(self.allocator);
    self.parser.deinit();
    self.scope.deinit(self.allocator);
}

pub fn render(self: @This(), a: Allocator) Error![]const u8 {
    var w = std.Io.Writer.Allocating.init(a);
    for (self.program.statements.items) |st| {
        try @import("render.zig").renderStatement(
            self.allocator,
            &w.writer,
            self.scope,
            st,
            self.json_opts,
        );
    }

    return try w.toOwnedSlice();
}
