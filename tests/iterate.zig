const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;
const Failure = shared.Failure;

test "iterate" {
    std.testing.log_level = .warn;

    runTest("STRUCT FIELD ITERATION", structFieldIteration);
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
