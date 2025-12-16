comptime {
    _ = @import("control_flow.zig");
    _ = @import("data.zig");
    _ = @import("lexing.zig");
}

const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

test "nested access test" {
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello World!
    ;

    const Nested = struct { inner: []const u8 };
    const TestStruct = struct { field: Nested };
    const Tmpl = zemplate.Template(TestStruct);
    var tmpl = Tmpl.init(.{ .field = .{ .inner = "World" } });
    const render = try tmpl.render(
        allocator,
        \\ Hello ||zz .field.inner zz||!
    ,
        .{},
    );
    defer allocator.free(render);

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
    print(
        \\
        \\ NEST Test PASSED
        \\
    , .{});
}

test "readme test" {
    // std.testing.log_level = .debug;
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello World!
    ;
    const TestTmpl =
        zemplate.Template(struct { field: []const u8 });

    var tmpl = TestTmpl.init(.{ .field = "World" });
    const render = try tmpl.render(allocator,
        \\ Hello ||zz .field zz||!
    , .{});
    defer allocator.free(render);

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
    print(
        \\
        \\ README Test PASSED
        \\
    , .{});
}

test "render test" {
    const Field2 =
        struct {
            str: []const u8,
            number: u32,
        };
    const Field5 =
        struct { num: u32 }; // std.testing.log_level = .debug;
    const Style = struct {
        background_color: []const u8,
        font_size: u32,
    };
    const Field6 =
        struct {
            style: Style,
            get: []const u8,
            id: []const u8,
        }; // std.testing.log_level = .debug;
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

    // const TestTemplate = zemplate.Template(Test, @embedFile("test.html"));
    const allocator = std.testing.allocator;
    var ctx = Test{ .field1 = std.ArrayList(u8).fromOwnedSlice(try allocator.dupe(u8, "this is a field")), .field2 = .{ .str = "hello world", .number = 42 }, .field3 = "section", .field4 = try allocator.dupe(u8, "this is field 4"), .field5 = &[_]Field5{
        .{ .num = 420 },
        .{ .num = 69 },
    }, .field6 = &[_]Field6{
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
    } };

    defer ctx.deinit(allocator);

    // var template = TestTemplate.init(ctx);
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
        \\        <div style='{"background_color":"black","font_size":10}' hx-get="myGet0" id="myId0">
        \\    </div>
        \\        <div style='{"background_color":"white","font_size":12}' hx-get="myGet1" id="myId1">
        \\    </div>
        \\    
        \\  </div>
        \\</div>
    ;
    const Tmpl = zemplate.Template(Test);
    var tmpl = Tmpl.init(ctx);

    const render = try tmpl.render(allocator, @embedFile("test.html"), .{ .whitespace = .minified });
    defer allocator.free(render);

    logDiff(expected, render);

    print(
        \\
        \\ Render Test PASSED
        \\
    , .{});
}

pub fn logDiff(expected: []const u8, actual: []const u8) void {
    if (std.mem.indexOfDiff(u8, expected, actual)) |idx| {
        const start = @max(idx, @as(usize, 10)) - 10;
        const end_expected = @min(expected.len, idx + 10);
        const end_actual = @min(actual.len, idx + 10);

        const exp_ctx = expected[start..end_expected];
        const act_ctx = actual[start..end_actual];

        std.log.err("❌ Render mismatch at index {d}", .{idx});

        std.log.err("Expected context ({}..{}): \"{s}\"", .{ start, end_expected, exp_ctx });
        std.log.err("Actual   context ({}..{}): \"{s}\"", .{ start, end_actual, act_ctx });

        std.log.err("Expected char: '{c}' (byte {d})", .{
            expected[idx], expected[idx],
        });
        std.log.err("Actual   char: '{c}' (byte {d})", .{
            actual[idx], actual[idx],
        });

        return;
    }
}
