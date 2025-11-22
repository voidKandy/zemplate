const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;

const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

test "lexer test" {
    // std.testing.log_level = .debug;
    const a =
        std.testing.allocator;
    const content =
        \\ <div>
        \\  ||zz .field zz||
        \\  <div attribute="||zz .attr zz||"></div>
    ;

    const expected = &[_]Token{
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "<div>",
            .typ = .generic,
        },
        .{
            .literal = "\n",
            .typ = .newline,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "||zz",
            .typ = .marker_open,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = ".field",
            .typ = .access,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "zz||",
            .typ = .marker_close,
        },
        .{
            .literal = "\n",
            .typ = .newline,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "<div",
            .typ = .generic,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "attribute=\"",
            .typ = .generic,
        },
        .{
            .literal = "||zz",
            .typ = .marker_open,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = ".attr",
            .typ = .access,
        },
        .{
            .literal = " ",
            .typ = .space,
        },
        .{
            .literal = "zz||",
            .typ = .marker_close,
        },
        .{
            .literal = "\"></div>",
            .typ = .generic,
        },
    };
    var lexer = Lexer.init(content[0..]);
    var i: usize = 0;
    while (try lexer.nextToken(a)) |next| : (i += 1) {
        const debug_str = try next.debugStr(a);
        defer a.free(debug_str);
        if (!expected[i].eql(next)) {
            const exp_debug_str = try expected[i].debugStr(a);
            defer a.free(exp_debug_str);

            std.debug.panic(
                \\ Token {d} Expected:
                \\ {s}
                \\ Got:
                \\ {s}
            , .{ i, exp_debug_str, debug_str });
        }
    }
    print("LEXER Test PASSED\n", .{});
}

test "readme test" {
    // std.testing.log_level = .debug;
    const allocator = std.testing.allocator;
    const MyContext = struct { field: []const u8 };

    const MyTemplate = zemplate.Template(MyContext,
        \\ Hello ||zz .field zz||!
    );

    var tmplt = MyTemplate.init(MyContext{ .field = "World" }, allocator);
    const expected =
        \\ Hello World!
    ;
    const render = try tmplt.render();
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
    print("README Test PASSED\n", .{});
}

test "render test" {
    // std.testing.log_level = .debug;
    const Test = struct {
        field1: []const u8,
        field2: []u8,
        field3: std.ArrayList(u8),

        fn deinit(self: *@This(), a: std.mem.Allocator) void {
            a.free(self.field2);
            self.field3.deinit(a);
        }
    };

    // test file contains:
    // <div>
    //    ||zz .field1 zz||
    //    <div style="||zz .field2 zz||">
    //    ||zz .field3 zz||
    //   </div>
    // </div>
    const TestTemplate = zemplate.Template(Test, @embedFile("test.html"));
    const allocator = std.testing.allocator;
    var ctx = Test{
        .field1 = "this is a field",
        .field2 = try allocator.dupe(u8, "this is field 2"),
        .field3 = std.ArrayList(u8).fromOwnedSlice(try allocator.dupe(u8, "this is field 3")),
    };

    defer ctx.deinit(allocator);

    var template = TestTemplate.init(ctx, allocator);
    const expected =
        \\<div>
        \\  this is a field
        \\  <div style="this is field 2">
        \\    this is field 3
        \\  </div>
        \\</div>
    ;

    const render = try template.render();
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

    print("Render Test PASSED\n", .{});
}
