const std = @import("std");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const runTest = @import("shared.zig").runTest;

test "rendering" {
    runTest("Iteration", iterationTest);
    // runTest("some", iterationTest);
}

const allocator = std.testing.allocator;

fn iterationTest() !void {
    const Test = struct {
        string: []const u8,
        with_string: struct { string: []const u8 },
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

    try zemplate.render_context.renderStatement(
        &w.writer,
        Test{
            .string = "outer string",
            .with_string = .{
                .string = "inner string",
            },
        },
        program.statements.items[0],
        .{},
    );
    std.log.err(
        \\ RENDER
        \\ {s}
    , .{w.written()});
}
