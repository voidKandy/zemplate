const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;

test "iterate" {
    std.testing.log_level = .warn;
    runTest("THREE ITERABLES", struct {
        fn run() !void {
            const allocator = std.testing.allocator;
            for (ALL_THREE_ITERABLE_CASES) |case| {
                if (try case.runTest(allocator)) |*failure| {
                    defer failure.deinit(allocator);
                    panic(
                        \\
                        \\ {s} Test Failed:
                        \\ {f}
                        \\
                    , .{ case.name, failure });
                } else {
                    print(
                        \\ {s}{s} CASE PASSED!{s}
                        \\
                    , .{ shared.ansi.GREEN, case.name, shared.ansi.RESET });
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
    expected: []u8,
    got: []u8,

    const CONTEXT_SIZE = 10;
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ Render mismatch at index {d}
        , .{self.index});
        try writer.print(
            \\ Expected context ({}..{}): "{s}"
        , .{
            self.start,
            self.exp_end,
            self.exp_ctx,
        });
        try writer.print(
            \\ Actual   context ({}..{}): "{s}"
        , .{
            self.start,
            self.got_end,
            self.got_ctx,
        });
        if (self.index < self.expected.len)
            try writer.print(
                \\ Expected char: '{c}' (byte {d})
            , .{
                self.expected[self.index],
                self.expected[self.index],
            })
        else
            try writer.writeAll("Given index is too large for expected content\n");

        if (self.index < self.got.len)
            try writer.print(
                \\ Actual   char: '{c}' (byte {d})
            , .{
                self.got[self.index],
                self.got[self.index],
            })
        else
            try writer.writeAll("Given index is too large for got content\n");
    }

    fn checkForFailure(a: std.mem.Allocator, got: []const u8, expected: []const u8) ?Failure {
        const idx = std.mem.indexOfDiff(u8, expected, got) orelse return null;
        const start = @max(idx, @as(usize, Failure.CONTEXT_SIZE)) - Failure.CONTEXT_SIZE;
        const end_expected = @min(expected.len, idx + Failure.CONTEXT_SIZE);
        const end_actual = @min(got.len, idx + Failure.CONTEXT_SIZE);
        const my_got = a.dupe(u8, got) catch @panic("out of memory");
        const my_expected = a.dupe(u8, expected) catch @panic("out of memory");

        const exp_ctx = my_expected[start..end_expected];
        const act_ctx = my_got[start..end_actual];
        return .{
            .index = idx,
            .start = start,
            .exp_end = end_expected,
            .got_end = end_actual,
            .exp_ctx = exp_ctx,
            .got_ctx = act_ctx,
            .expected = my_expected,
            .got = my_got,
        };
    }

    fn deinit(self: *@This(), a: std.mem.Allocator) void {
        a.free(self.got);
        a.free(self.expected);
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
            return Failure.checkForFailure(a, got, self.expected);
        }
    };
}

const TypeWithInnerString = struct { inner_string: []const u8 = "" };
const ThreeIterableCtx = struct {
    outer_field: []const u8 = "",
    array: []const []const u8 = &[_][]const u8{},
    structs: []const TypeWithInnerString = &[_]TypeWithInnerString{},
    inner_struct: TypeWithInnerString = .{},
};

const ALL_THREE_ITERABLE_CASES = &[_]ForLoopTestCase(ThreeIterableCtx){
    .{
        .name = "three iterables",
        .content =
        \\ Hello!
        \\||zz for .outer_field zz||
        \\ {{.}}
        \\||zz endfor zz||
        \\Amt array: ||zz .array.len zz||
        \\||zz for .array zz||
        \\ {{ . }}
        \\||zz endfor zz||
        \\Amt Structs: ||zz .structs.len zz||
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
        \\Amt array: 3
        \\ one
        \\ two
        \\ three
        \\
        \\Amt Structs: 2
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
        \\{{.inner_string}}
        \\||zz for .inner_string zz||
        \\ {{.}}
        \\||zz endfor zz||
        \\{{.inner_string}}
        \\||zz endfor zz||
        \\
        \\||zz for .inner_struct.inner_string zz||
        \\ {{.}}
        \\||zz endfor zz||
        ,
        .expected =
        \\myTest1
        \\ m
        \\ y
        \\ T
        \\ e
        \\ s
        \\ t
        \\ 1
        \\
        \\myTest1
        \\myTest2
        \\ m
        \\ y
        \\ T
        \\ e
        \\ s
        \\ t
        \\ 2
        \\
        \\myTest2
        \\
        \\
        \\ W
        \\ a
        \\ t
        \\ e
        \\ r
        \\ m
        \\ e
        \\ l
        \\ o
        \\ n
        \\
        ,
        .ctx = .{
            .structs = &[_]TypeWithInnerString{
                .{ .inner_string = "myTest1" },
                .{ .inner_string = "myTest2" },
            },
            .inner_struct = TypeWithInnerString{
                .inner_string = "Watermelon",
            },
        },
    },
};
