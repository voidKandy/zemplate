const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;
const Failure = shared.Failure;

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
