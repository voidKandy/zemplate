const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;
const Failure = shared.Failure;

test "iterate" {
    std.testing.log_level = .warn;

    runTest("CUSTOM ITERATOR", customIterator);
    runTest("STRUCT FIELD ITERATION", structFieldIteration);

    // runTest("THREE ITERABLES", struct {
    //     fn run() !void {
    //         const allocator = std.testing.allocator;
    //         for (ALL_THREE_ITERABLE_CASES) |case| {
    //             if (try case.runTest(allocator)) |*failure| {
    //                 defer failure.deinit(allocator);
    //                 panic(
    //                     \\
    //                     \\ {s} Test Failed:
    //                     \\ {f}
    //                     \\
    //                 , .{ case.name, failure });
    //             } else {
    //                 print(
    //                     \\ {s}{s} CASE PASSED!{s}
    //                     \\
    //                 , .{ shared.ansi.GREEN, case.name, shared.ansi.RESET });
    //             }
    //         }
    //     }
    // }.run);
}

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
        \\ {|.|}
        \\||zz endfor zz||
        \\Amt array: ||zz .array.len zz||
        \\||zz for .array zz||
        \\ {| . |}
        \\||zz endfor zz||
        \\Amt Structs: ||zz .structs.len zz||
        \\||zz for .structs zz||
        \\ {| .inner_string |}
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
        \\{|.inner_string|}
        \\||zz for .inner_string zz||
        \\ {|.|}
        \\||zz endfor zz||
        \\{|.inner_string|}
        \\||zz endfor zz||
        \\
        \\||zz for .inner_struct.inner_string zz||
        \\ {|.|}
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

const VisitorCtx = struct {
    pub fn visit(self: *@This(), val: anytype) zemplate.Error!void {
        _ = self;
        _ = val;
    }
};

fn structFieldIteration() !void {
    const OtherStruct = struct {
        other_string: []const u8,
    };
    const TestStruct = struct {
        other: ?OtherStruct,
        string: []const u8,
        number: u64,

        fn eql(self: @This(), other: @This()) bool {
            return (std.mem.eql(u8, self.string, other.string) and
                (self.other == null and other.other == null or std.mem.eql(u8, self.other.?.other_string, other.other.?.other_string)) and
                self.number == other.number);
        }

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print(
                \\ string: {s}
                \\ number: {d}
                \\ other: {any}
            , .{ self.string, self.number, self.other });
        }
    };
    const expected_strings =
        &[_][]const u8{
            "one",
            "two",
            "three",
        };

    const expected_structs =
        &[_]TestStruct{
            .{
                .string = "alpha zebra",
                .number = 42,
                .other = .{ .other_string = "inner-one" },
            },
            .{
                .string = "moon quartz",
                .number = 987654321,
                .other = .{ .other_string = "inner-two" },
            },
            .{
                .string = "river echo",
                .number = 1337,
                .other = .{ .other_string = "inner-three" },
            },
            .{
                .string = "sky lantern",
                .number = 555555,
                .other = .{ .other_string = "inner-four" },
            },
            .{
                .string = "ghost ember",
                .number = 777777777,
                .other = .{ .other_string = "inner-five" },
            },
        };
    var parent = .{
        .strings = expected_strings,
        .structs = expected_structs,
    };

    {
        var iter = zemplate.iterate.StructFieldIterator(@TypeOf(parent), "strings").fromParentPtr(&parent);
        var i: usize = 0;
        while (iter.next()) |n| : (i += 1) {
            if (!std.mem.eql(u8, n.*, expected_strings[i])) {
                std.log.err(
                    \\ Expected:
                    \\ {s}
                    \\ Got:
                    \\ {s}
                , .{ expected_strings[i], n.* });
                @panic("failed");
            }
        }
    }
    {
        var iter = zemplate.iterate.StructFieldIterator(@TypeOf(parent), "structs").fromParentPtr(&parent);
        var i: usize = 0;
        while (iter.next()) |n| : (i += 1) {
            if (!n.eql(expected_structs[i])) {
                std.log.err(
                    \\ Expected:
                    \\ {f}
                    \\ Got:
                    \\ {f}
                , .{ expected_structs[i], n });
                @panic("failed");
            }
        }
    }
}

fn customIterator() !void {
    var inst =
        ThreeIterableCtx{
            .outer_field = "some string",
            .array = &[_][]const u8{
                "data", "other data",
            },
            .structs = &[_]TypeWithInnerString{
                .{
                    .inner_string = "Inner",
                },
            },
        };
    var ctx = try zemplate.iterate.StructIterationContext(VisitorCtx).init(ThreeIterableCtx, &inst, std.testing.allocator);
    defer ctx.deinit(std.testing.allocator);
    var vctx: VisitorCtx = .{};

    for (ctx.fields.values()) |f| {
        const n = f.next() orelse continue;
        try f.visit(&vctx, n);
    }
}
