const std = @import("std");
const shared = @import("shared.zig");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const runTest = @import("shared.zig").runTest;

test "rendering" {
    runTest("Render For Loop", renderForLoopTest);
}

const allocator = std.testing.allocator;

const TestCase = struct {
    obj: Test,
    inputs_and_expected: []const IandE,

    const IandE =
        struct {
            input: []const u8,
            expected: []const u8,
        };
    const Other = struct {
        string: []const u8,
    };
    const Test = struct {
        variable: u32,
        inner: Other,
        arr: []const Other,
        string: []const u8,
    };

    fn runTest(self: @This()) anyerror!void {
        var w = std.Io.Writer.Allocating.init(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);
        const a = arena.allocator();
        defer {
            arena.deinit();
            w.deinit();
        }

        for (self.inputs_and_expected) |iande| {
            var lexer = Lexer.init(iande.input);
            var parser = try Parser.init(a, &lexer, null);
            const program = try parser.parseProgram();
            const scope = try zemplate.Scope.init(Test, &self.obj, a);
            defer scope.deinit(a);

            for (program.statements.items) |st| {
                try zemplate.render.renderStatement(
                    a,
                    &w.writer,
                    scope,
                    st,
                    .{},
                );
            }

            shared.logDiff(iande.expected, w.written()) catch |e| {
                std.log.err(
                    \\Expected:
                    \\{s}
                    \\Got:
                    \\{s}
                , .{ iande.expected, w.written() });
                return e;
            };
        }
    }
};

fn renderForLoopTest() !void {
    const case = TestCase{
        .obj = TestCase.Test{
            .variable = 42,
            .string = "outer string",
            .inner = .{ .string = "inner string" },
            .arr = &[_]TestCase.Other{
                .{
                    .string = "one",
                },
                .{
                    .string = "two",
                },
            },
        },
        .inputs_and_expected = &[_]TestCase.IandE{.{ .input = 
        \\ ||zz for .string zz||
        \\ {|.|}
        \\ ||zz endfor zz||
        , .expected = 
        \\o
        \\ u
        \\ t
        \\ e
        \\ r
        \\  
        \\ s
        \\ t
        \\ r
        \\ i
        \\ n
        \\ g
        \\ 
    }},
    };

    try case.runTest();
}
