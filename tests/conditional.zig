const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;

test "conditional" {
    std.testing.log_level = .warn;

    runTest("THREE CONDITIONALS", struct {
        fn run() !void {
            const allocator = std.testing.allocator;
            for (ALL_THREE_CONDITIONAL_CASES) |case| {
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

const ThreeConditionalCtx = struct {
    str_payload: ?[]const u8 = null,
    struct_payload: ?struct {
        inner_str: ?[]const u8 = null,
        boolean: bool,
    } = null,
    boolean: bool,
};

const ALL_THREE_CONDITIONAL_CASES = &[_]ConditionalTestCase(ThreeConditionalCtx){
    .{
        .name = "three conditionals",
        .input =
        \\ ||zz if .str_payload zz||
        \\PAYLOAD: {{.}}
        \\ ||zz else zz||
        \\NO PAYLOAD
        \\ ||zz endif zz||
        \\
        \\ ||zz if .boolean zz||
        \\the sky is usually blue
        \\ ||zz else zz||
        \\the sky is usually orange
        \\ ||zz endif zz||
        \\ 
        \\ ||zz if .struct_payload zz||
        \\Struct payload exists
        \\ ||zz if .inner_str zz||
        \\Inner String: {{.}}
        \\ ||zz else zz||
        \\ there is no inner_str
        \\ ||zz endif zz||
        \\
        \\ ||zz if .boolean zz||
        \\The inner boolean is true
        \\ ||zz else zz||
        \\The inner boolean is false
        \\ ||zz endif zz||
        \\
        \\ ||zz else zz||
        \\There is no struct payload
        \\ ||zz endif zz||
        \\
        ,
        .ctx_and_expected = &[_]ConditionalTestCase(ThreeConditionalCtx).Expected{
            .{
                .ctx = .{
                    .str_payload = "some string payload",
                    .boolean = false,
                    .struct_payload = .{
                        .inner_str = "some inner string",
                        .boolean = true,
                    },
                },
                .expected =
                \\PAYLOAD: some string payload
                \\the sky is usually orange
                \\
                \\Struct payload exists
                \\Inner String: some inner string
                \\The inner boolean is true
                ,
            },
        },
    },
};

fn ConditionalTestCase(comptime TemplateContext: type) type {
    return struct {
        name: []const u8,
        input: []const u8,
        ctx_and_expected: []const Expected,

        pub const Expected =
            struct {
                ctx: TemplateContext,
                expected: []const u8,
            };
        const Template = zemplate.Template(TemplateContext);

        pub fn runTest(self: @This(), a: std.mem.Allocator) anyerror!?Failure {
            for (self.ctx_and_expected) |ctx_and_exp| {
                var tmpl = Template.init(ctx_and_exp.ctx);
                const got = try tmpl.render(a, self.input, .{ .whitespace = .minified });
                defer a.free(got);
                return Failure.checkForFailure(a, got, ctx_and_exp.expected);
            }
            return null;
        }
    };
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
