const std = @import("std");
const shared = @import("shared.zig");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const runTest = @import("shared.zig").runTest;

test "rendering" {
    runTest("Render For Loop", renderForLoopTest);
    runTest("Render If", renderIfTest);
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
        opt: ?[]const u8 = null,
        boolean: bool = false,
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
            var parser = try Parser.init(a, &lexer);
            var program = parser.parseProgram(a) catch return parser.logErrors(std.log);
            defer program.statements.deinit(a);
            const scope = try zemplate.Scope.init(&self.obj, a);
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
            try std.testing.expectEqualStrings(iande.expected, w.written());
            w.clearRetainingCapacity();
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
        .inputs_and_expected = &[_]TestCase.IandE{
            .{ .input =
            \\ ||zz for .string zz||
            \\ {|.|}
            \\ ||zz endfor zz||
            , .expected =
            \\ o
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
            },
            .{ .input =
            \\ ||zz for .arr zz||
            \\ {|.string |}
            \\ ||zz endfor zz||
            , .expected =
            \\ one
            \\ two
            \\ 
            },
        },
    };

    try case.runTest();
}

fn renderIfTest() !void {
    const obj = TestCase.Test{
        .variable = 42,
        .string = "outer string",
        .opt = "optional",
        .inner = .{ .string = "inner string" },
        .arr = &[_]TestCase.Other{
            .{
                .string = "one",
            },
            .{
                .string = "two",
            },
        },
    };

    const cases = &[_]TestCase{
        .{
            .obj = obj,
            .inputs_and_expected = &[_]TestCase.IandE{.{ .input =
            \\ ||zz if .opt zz||
            \\ {|.|}
            \\ ||zz endif zz||
            , .expected =
            \\ optional
            \\ 
            }},
        },
        .{
            .obj = blk: {
                var o = obj;
                o.opt = null;
                break :blk o;
            },
            .inputs_and_expected = &[_]TestCase.IandE{.{ .input =
            \\ ||zz if .opt zz||
            \\ {|.|}
            \\ ||zz endif zz||
            , .expected =
            \\ 
            \\ 
            }},
        },
        .{
            .obj = blk: {
                var o = obj;
                o.boolean = true;
                break :blk o;
            },
            .inputs_and_expected = &[_]TestCase.IandE{.{ .input =
            \\ ||zz if .opt zz||
            \\ ||zz for . zz||
            \\ {|.|}
            \\ ||zz endfor zz||
            \\ {|..string|}
            \\ ||zz if ..variable == 42 zz||
            \\ {|..variable|} == 42
            \\ ||zz else zz||
            \\ {|..variable|} != 42
            \\ ||zz endif zz||
            \\ ||zz if ..boolean == true zz||
            \\ {|..boolean|} == true
            \\ ||zz else zz||
            \\ {|..boolean|} != true
            \\ ||zz endif zz||
            \\ ||zz if ..inner.string == 'inner string' zz||
            \\ {|..inner.string|} == 'inner string'
            \\ ||zz else zz||
            \\ {|..inner.string|} != 'inner string'
            \\ ||zz endif zz||
            \\ ||zz endif zz||
            , .expected =
            \\ o
            \\ p
            \\ t
            \\ i
            \\ o
            \\ n
            \\ a
            \\ l
            \\ 
            \\ outer string
            \\ 42 == 42
            \\ 
            \\ true == true
            \\ 
            \\ inner string == 'inner string'
            \\ 
            \\ 
            }},
        },
    };

    for (cases) |case|
        try case.runTest();
}
