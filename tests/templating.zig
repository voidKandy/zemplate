const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const runTest = @import("shared.zig").runTest;
const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

test "templating" {
    std.testing.log_level = .info;
    runTest("NESTED ACCESS", nestedAccessTest);
    runTest("README", readmeTest);
    runTest("RENDER", renderTest);
}

fn nestedAccessTest() !void {
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello World!
    ;

    const Nested = struct {
        inner: []const u8,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll("NESTED");
            try writer.writeAll(self.inner);
        }
    };
    const TestStruct = struct {
        field: Nested,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll("TESTSTRUCT");
            try writer.print("{f}", .{self.field});
        }
    };

    var tmpl = try zemplate.Template(TestStruct).init(allocator, TestStruct{ .field = .{ .inner = "World" } });
    defer tmpl.deinit();

    const render = try tmpl.render(
        \\ Hello {|.field.inner|}!
    ,
        .{},
    );

    if (!std.mem.eql(u8, expected, render)) {
        std.log.err(
            \\ did not get expected render!
            \\ Expected:
            \\ {s}
            \\ got:
            \\ {s}
            \\
        , .{ expected, render });
        return error.TestFailure;
    }
}

fn readmeTest() !void {
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello World!
    ;

    const Test = struct { field: []const u8 };

    var tmpl = try zemplate.Template(Test).init(
        allocator,
        Test{ .field = "World" },
    );
    defer tmpl.deinit();

    const render = try tmpl.render(
        \\ Hello {|.field|}!
    , .{});

    if (!std.mem.eql(u8, expected, render)) {
        std.log.err(
            \\ did not get expected render!
            \\ Expected:
            \\ {s}
            \\ got:
            \\ {s}
            \\
        , .{ expected, render });
        return;
    }
}

fn renderTest() !void {
    const Field2 = struct {
        str: []const u8,
        number: u32,
    };
    const Field5 = struct { num: u32 };
    const Style = struct {
        background_color: []const u8,
        font_size: u32,
    };
    const Field6 = struct {
        style: Style,
        get: []const u8,
        id: []const u8,
    };

    const Test = struct {
        field1: std.ArrayList(u8),
        field2: Field2,
        field3: []const u8,
        field4: []u8,
        field5: []const Field5,
        field6: []const Field6,

        fn deinit(self: *@This(), a: std.mem.Allocator) void {
            self.field1.deinit(a);
            a.free(self.field4);
        }
    };

    const allocator = std.testing.allocator;

    var ctx = Test{
        .field1 = std.ArrayList(u8).fromOwnedSlice(
            try allocator.dupe(u8, "this is a field"),
        ),
        .field2 = .{ .str = "hello world", .number = 42 },
        .field3 = "section",
        .field4 = try allocator.dupe(u8, "this is field 4"),
        .field5 = &[_]Field5{
            .{ .num = 420 },
            .{ .num = 69 },
        },
        .field6 = &[_]Field6{
            .{
                .id = "myId0",
                .get = "myGet0",
                .style = .{
                    .background_color = "black",
                    .font_size = 10,
                },
            },
            .{
                .id = "myId1",
                .get = "myGet1",
                .style = .{
                    .background_color = "white",
                    .font_size = 12,
                },
            },
        },
    };
    defer ctx.deinit(allocator);

    const expected =
        \\<div>
        \\  this is a field
        \\  <div style="{"str":"hello world","number":42}">
        \\    <section>
        \\      this is field 4
        \\    </section>
        \\    <script type="application/json">
        \\    [{"num":420},{"num":69}]
        \\    </script>
        \\
        \\    <div style='{"background_color":"black","font_size":10}' hx-get="myGet0" id="myId0">
        \\    </div>
        \\
        \\    <div style='{"background_color":"white","font_size":12}' hx-get="myGet1" id="myId1">
        \\    </div>
        \\
        \\  </div>
        \\</div>
    ;

    const input =
        \\<div>
        \\  {| .field1.items |}
        \\  <div style="{|.field2 json |}">
        \\    <{| .field3 |}>
        \\      {| .field4 |}
        \\    </{| .field3 |}>
        \\    <script type="application/json">
        \\    {| .field5 json |}
        \\    </script>
        \\    ||zz for .field6 zz||
        \\    <div style='{|.style json|}' hx-get="{|.get|}" id="{|.id|}">
        \\    </div>
        \\    ||zz endfor zz||
        \\  </div>
        \\</div>
    ;
    var tmpl = try zemplate.Template(Test).init(
        allocator,
        ctx,
    );
    defer tmpl.deinit();

    const render = try tmpl.render(
        input,
        .{ .whitespace = .minified },
    );

    const sani_expected = try removeWhitespace(expected);
    const sani_render = try removeWhitespace(render);

    defer {
        std.testing.allocator.free(sani_expected);
        std.testing.allocator.free(sani_render);
    }

    try std.testing.expectEqualStrings(sani_expected, sani_render);
}

fn removeWhitespace(input: []const u8) anyerror![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(std.testing.allocator, input.len);

    for (input) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            continue;
        }
        try result.append(std.testing.allocator, ch);
    }

    return result.toOwnedSlice(std.testing.allocator);
}
