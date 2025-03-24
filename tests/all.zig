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

    const render = try template.render();
    defer render.deinit();

    if (!std.mem.eql(u8, expected, render.items)) {
        std.debug.panic("did not get expected render!\nExpected: {s}\ngot: {s}\n", .{ expected, render.items });
    }
}

const Lexer = zemplate.template.parse.Lexer;
const TokenType = zemplate.template.parse.TokenType;
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
    var tokens = try lexer.process_input(arena.allocator());

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
    while (tokens.pop()) |t| : (i += 1) {
        const trimmed_ex = std.mem.trim(u8, expected[i].content, " \n");
        const trimmed_got = std.mem.trim(u8, t.data.content, " \n");
        if (!std.mem.eql(u8, trimmed_ex, trimmed_got)) {
            std.debug.panic("Trimmed incorrect!\nExpected: [{s}]\nGot: [{s}]\n", .{ trimmed_ex, trimmed_got });
        }
        if (!std.meta.eql(expected[i].typ, t.data.typ)) {
            std.debug.panic("Type incorrect!\nExpected, {any}\nGot: {any}\n", .{ expected[i].typ, t.data.typ });
        }
    }
}
