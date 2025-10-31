const std = @import("std");
const zemplate = @import("zemplate");

const Test = struct { field: []const u8, attr: []const u8 };
const TestTemplate = zemplate.template.Template(Test, @embedFile("test.html"));
// test file contains:
// <div>
//  ||zz .field zz||
//  <div attribute="||zz .attr zz||"></div>

test "render test" {
    const allocator = std.testing.allocator;
    var template = try TestTemplate.init(Test{ .field = "mom", .attr = "this-attr" }, allocator);
    const expected =
        \\<div>
        \\  mom
        \\  <div attribute="this-attr"></div>
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

const Lexer = zemplate.template.parse.Lexer;
const TokenType = zemplate.template.parse.TokenType;
const Token = zemplate.template.parse.Token;
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
