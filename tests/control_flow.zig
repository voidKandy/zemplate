const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const runTest = @import("shared.zig").runTest;

test "control flow" {
    runTest("THREE ITERABLES", struct {
        fn run() !void {
            const allocator = std.testing.allocator;
            for (ALL_THREE_ITERABLE_CASES) |case| {
                if (try case.runTest(allocator)) |failure| {
                    panic(
                        \\
                        \\ {s} Test Failed:
                        \\ {f}
                        \\
                    , .{ case.name, failure });
                }
            }
        }
    }.run);
}

const Failure = struct {
    index: usize,
    start: usize,
    exp_end: usize,
    got_end: usize,
    exp_ctx: []const u8,
    got_ctx: []const u8,
    expected: []const u8,
    got: []const u8,

    const CONTEXT_SIZE = 10;
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ Render mismatch at index {d}
            \\ Expected context ({}..{}): "{s}"
            \\ Actual   context ({}..{}): "{s}"
            \\ Expected char: '{c}' (byte {d})
            \\ Actual   char: '{c}' (byte {d})
        , .{
            self.index,
            self.start,
            self.exp_end,
            self.exp_ctx,
            self.start,
            self.got_end,
            self.got_ctx,
            self.expected[self.index],
            self.expected[self.index],
            self.got[self.index],
            self.got[self.index],
        });
    }

    fn checkForFailure(got: []const u8, expected: []const u8) ?Failure {
        const idx = std.mem.indexOfDiff(u8, expected, got) orelse return null;
        const start = @max(idx, @as(usize, Failure.CONTEXT_SIZE)) - Failure.CONTEXT_SIZE;
        const end_expected = @min(expected.len, idx + Failure.CONTEXT_SIZE);
        const end_actual = @min(got.len, idx + Failure.CONTEXT_SIZE);

        const exp_ctx = expected[start..end_expected];
        const act_ctx = got[start..end_actual];
        return .{
            .index = idx,
            .start = start,
            .exp_end = end_expected,
            .got_end = end_actual,
            .exp_ctx = exp_ctx,
            .got_ctx = act_ctx,
            .expected = expected,
            .got = got,
        };
    }
};

fn ForLoopTestCase(comptime TemplateContext: type) type {
    return struct {
        name: []const u8,
        ctx: TemplateContext,
        content: []const u8,
        expected: []const u8,

        const Template = zemplate.Template(TemplateContext);

        pub fn runTest(self: @This(), a: std.mem.Allocator) anyerror!?Failure {
            var tmpl = Template.init(self.ctx);
            const got = try tmpl.render(a, self.content, .{ .whitespace = .minified });
            defer a.free(got);
            return Failure.checkForFailure(got, self.expected);
        }
    };
}

const TypeWithInnerString = struct { inner_string: []const u8 };
const ThreeIterableCtx = struct {
    outer_field: []const u8 = "",
    array: []const []const u8 = &[_][]const u8{},
    structs: []const TypeWithInnerString = &[_]TypeWithInnerString{},
};

const ALL_THREE_ITERABLE_CASES = &[_]ForLoopTestCase(ThreeIterableCtx){
    .{
        .name = "three iterables",
        .content =
        \\ Hello!
        \\||zz for .outer_field zz||
        \\ {{.}}
        \\||zz endfor zz||
        \\||zz for .array zz||
        \\ {{ . }}
        \\||zz endfor zz||
        \\||zz for .structs zz||
        \\ {{ .inner_string }}
        \\||zz endfor zz||
        \\
        ,
        .expected =
        \\ Hello!
        \\ W
        \\ o
        \\ r
        \\ l
        \\ d
        \\
        \\ one
        \\ two
        \\ three
        \\
        \\ string
        \\ string2
        \\
        \\
        ,
        .ctx = .{
            .outer_field = "World",
            .array = &[_][]const u8{
                "one",
                "two",
                "three",
            },
            .structs = &[_]TypeWithInnerString{
                .{ .inner_string = "string" },
                .{ .inner_string = "string2" },
            },
        },
    },
    .{
        .name = "nested for loops",
        .content =
        \\||zz for .structs zz||
        \\||zz for . zz||
        \\ {{..}} - {{.}}
        \\||zz endfor zz||
        \\||zz endfor zz||
        \\
        ,
        .expected =
        \\ myTest1 - m
        \\ myTest1 - y
        \\ myTest1 - T
        \\ myTest1 - e
        \\ myTest1 - s
        \\ myTest1 - t
        \\ myTest1 - 1
        \\
        \\ myTest2 - m
        \\ myTest2 - y
        \\ myTest2 - T
        \\ myTest2 - e
        \\ myTest2 - s
        \\ myTest2 - t
        \\ myTest2 - 2
        \\
        \\
        ,
        .ctx = .{
            .structs = &[_]TypeWithInnerString{
                .{ .inner_string = "myTest1" },
                .{ .inner_string = "myTest2" },
            },
        },
    },
};
