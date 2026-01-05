const std = @import("std");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const print = std.debug.print;
const panic = std.debug.panic;
const runTest = @import("shared.zig").runTest;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const Token = zemplate.Token;

test "parsing" {
    std.testing.log_level = .warn;
    runTest("PARSING", parserTest);
}

const ParserTestCase = struct {
    name: []const u8,
    content: []const u8,
    expected_statements: []const ast.Statement,

    const Failure = struct {
        idx: usize,
        expected: ast.Statement,
        got: ast.Statement,

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print(
                \\ --- Failure at Statement {d} ---
                \\ expected: {f}
                \\ got: {f}
            , .{ self.idx, self.expected, self.got });
        }
    };

    fn runTest(self: @This(), a: std.mem.Allocator) anyerror!?Failure {
        var lexer = Lexer.init(self.content[0..]);
        var parser = try Parser.init(a, &lexer, null);
        // defer parser.deinit();
        const program = try parser.parseProgram();

        if (parser.errors.items.len > 0) {
            return error.HasError;
        }
        for (program.statements.items, 0..) |statement, i| {
            if (!self.expected_statements[i].eql(statement)) {
                return .{
                    .idx = i,
                    .expected = self.expected_statements[i],
                    .got = statement,
                };
            }
        }
        return null;
    }
};

fn parserTest() !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (try initCases(arena.allocator())) |case| {
        if (try case.runTest(arena.allocator())) |failure| {
            std.log.err(
                \\
                \\ {s} Test Failed:
                \\ {f}
                \\
            , .{ case.name, failure });
            return error.Failure;
        }
    }
}

fn initCases(a: std.mem.Allocator) std.mem.Allocator.Error![]ParserTestCase {
    return try a.dupe(ParserTestCase, &[_]ParserTestCase{
        .{
            .name = "all statements",
            .content =
            \\ ||zz if .something zz||
            \\ {|.|}
            \\ {|.subfield|}
            \\ ||zz endif zz||
            \\ ||zz for .iterable json zz||
            \\ {|.|}
            \\ ||zz endfor zz||
            ,
            .expected_statements = &[_]ast.Statement{
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{ .access = .{
                            .literal = try a.dupe(u8, ".something"),
                        } }),
                        .block = .{ .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                            .{ .expression = try ast.ExpressionStatement.create(a, .{ .access = .{
                                .literal = try a.dupe(u8, "."),
                            } }) },
                            .{ .expression = try ast.ExpressionStatement.create(a, .{ .access = .{
                                .literal = try a.dupe(u8, ".subfield"),
                            } }) },
                        }) },
                        .alternative = null,
                    },
                },
                .{
                    .@"for" = .{
                        .access = .{
                            .literal = try a.dupe(u8, ".iterable"),
                            .json = true,
                        },
                        .block = .{ .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                            .{ .expression = try ast.ExpressionStatement.create(a, .{ .access = .{
                                .literal = try a.dupe(u8, "."),
                            } }) },
                        }) },
                        .alternative = null,
                    },
                },
            },
        },
    });
}
