const std = @import("std");
const zemplate = @import("zemplate");
const Lexer = zemplate.parse.Lexer;
const TokenType = zemplate.parse.TokenType;
const Token = zemplate.parse.Token;

test "readme test" {
    const allocator = std.testing.allocator;
    const MyContext = struct { field: []const u8 };

    const MyTemplate = zemplate.Template(MyContext,
        \\ Hello ||zz .field zz||!
    );

    var tmplt = MyTemplate.init(MyContext{ .field = "World" }, allocator);
    const expected =
        \\ Hello World!
    ;
    var render = try tmplt.render();
    defer render.deinit(allocator);

    if (!std.mem.eql(u8, expected, render.items)) {
        std.log.err(
            \\ did not get expected render!
            \\ Expected:
            \\ {s}
            \\ got:
            \\ {s}
            \\
        , .{ expected, render.items });
        return;
    }
    std.debug.print("README Test PASSED\n", .{});
}

test "render test" {
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

    var render = try template.render();
    defer render.deinit(allocator);

    if (!std.mem.eql(u8, expected, render.items)) {
        std.log.err(
            \\ did not get expected render!
            \\ Expected:
            \\ {s}
            \\ got:
            \\ {s}
            \\
        , .{ expected, render.items });
        return;
    }

    std.debug.print("Render Test PASSED\n", .{});
}

test "lexing test" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const content =
        \\ <div>
        \\  ||zz .field zz||
        \\  <div attribute="||zz .attr zz||"></div>
    ;
    var lexer = Lexer.init(content[0..]);
    try lexer.processInput(arena.allocator());

    const expected: [9]struct { content: []const u8, typ: TokenType } = .{ .{
        .content = "<div>",
        .typ = TokenType.Block,
    }, .{
        .content = "||zz",
        .typ = TokenType.MarkerOpen,
    }, .{
        .content = ".field",
        .typ = TokenType.Access,
    }, .{
        .content = "zz||",
        .typ = TokenType.MarkerClose,
    }, .{
        .content = "<div attribute=\"",
        .typ = TokenType.Block,
    }, .{
        .content = "||zz",
        .typ = TokenType.MarkerOpen,
    }, .{
        .content = ".attr",
        .typ = TokenType.Access,
    }, .{
        .content = "zz||",
        .typ = TokenType.MarkerClose,
    }, .{
        .content = "\"></div>",
        .typ = TokenType.Block,
    } };

    var i: usize = 0;

    var current_node: ?*std.DoublyLinkedList.Node = &lexer.head.?.node;

    // while (tokens.pop()) |t| : (i += 1) {
    while (current_node) |n| {
        const t: *Token = @fieldParentPtr("node", n);
        const trimmed_ex = std.mem.trim(u8, expected[i].content, " \n");
        const trimmed_got = std.mem.trim(u8, t.content, " \n");
        if (!std.mem.eql(u8, trimmed_ex, trimmed_got)) {
            std.log.err(
                \\ Trimmed incorrect!
                \\ Expected:
                \\ [{s}]
                \\ Got:
                \\ [{s}]
                \\
            , .{ trimmed_ex, trimmed_got });
            return;
        }
        if (!std.meta.eql(expected[i].typ, t.typ)) {
            std.log.err(
                \\ Type incorrect!
                \\ Expected:
                \\ {any}
                \\ Got:
                \\ {any}
                \\
            , .{ expected[i].typ, t.typ });
            return;
        }

        i += 1;
        current_node = t.node.next;
    }
    std.debug.print("Lexing Test PASSED\n", .{});
}
