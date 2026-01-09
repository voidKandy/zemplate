const std = @import("std");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const runTest = @import("shared.zig").runTest;

test "rendering" {
    runTest("Render For Loop", renderForLoopTest);
    // runTest("some", iterationTest);
}

const allocator = std.testing.allocator;

fn renderForLoopTest() !void {
    const Other = struct {
        string: []const u8,
    };
    const Test = struct {
        variable: u32,
        inner: Other,
        arr: []const Other,
        string: []const u8,
    };
    var w = std.Io.Writer.Allocating.init(allocator);
    var arena = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();

    defer {
        arena.deinit();
        w.deinit();
    }
    var lexer = Lexer.init(
        \\ ||zz for .string zz||
        \\ {|.|}
        \\ ||zz endfor zz||
    );
    var parser = try Parser.init(a, &lexer, null);
    const program = try parser.parseProgram();
    const t =
        Test{
            .variable = 42,
            .string = "outer string",
            .inner = .{ .string = "inner string" },
            .arr = &[_]Other{
                .{
                    .string = "one",
                },
                .{
                    .string = "two",
                },
            },
        };
    const scope = try zemplate.scope.Scope.init(&t, a);
    // const Scope = try zemplate.scope.Scope(Test);
    // const scope = Scope.init(t);

    try zemplate.render_context.renderStatement(
        a,
        &w.writer,
        scope,
        program.statements.items[0],
        .{},
    );
    std.log.err(
        \\ RENDER
        \\ {s}
    , .{w.written()});
}
