const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const runTest = @import("shared.zig").runTest;

test "data" {
    runTest("CUSTOM ITERATOR", customIterator);
    runTest("STRUCT ITERATION", structIteration);
}

fn structIteration() !void {
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
        var iter = (try zemplate.iterate.StructFieldIterator(@TypeOf(parent), "strings")).fromParentPtr(&parent);
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
        var iter = (try zemplate.iterate.StructFieldIterator(@TypeOf(parent), "structs")).fromParentPtr(&parent);
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

const TypeWithInnerString = struct { inner_string: []const u8 };
const ThreeIterableCtx = struct {
    outer_field: []const u8 = "",
    array: []const []const u8 = &[_][]const u8{},
    structs: []const TypeWithInnerString = &[_]TypeWithInnerString{},
};

const VisitorCtx = struct {
    pub fn visit(self: *@This(), val: anytype) zemplate.Error!void {
        _ = self;
        _ = val;
    }
};

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
    var ctx = try zemplate.newiterate.StructIterationContext(VisitorCtx).init(ThreeIterableCtx, &inst, std.testing.allocator);
    defer ctx.deinit(std.testing.allocator);
    var vctx: VisitorCtx = .{};

    for (ctx.fields.values()) |f| {
        const n = f.next() orelse continue;
        try f.visit(&vctx, n);
    }
}
