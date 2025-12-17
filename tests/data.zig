const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const runTest = @import("shared.zig").runTest;

test "data" {
    runTest("CUSTOM ITERATOR", customIterator);
}

fn customIterator() !void {
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
            if (!std.mem.eql(u8, n, expected_strings[i])) {
                std.log.err(
                    \\ Expected:
                    \\ {s}
                    \\ Got:
                    \\ {s}
                , .{ expected_strings[i], n });
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
