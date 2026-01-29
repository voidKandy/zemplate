const std = @import("std");
const zemplate = @import("zemplate");
const shared = @import("shared.zig");
const runTest = @import("shared.zig").runTest;
const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

test "lexing" {
    std.testing.log_level = .warn;
    runTest("LEXING", lexerTest);
}

const LexerTestCase = struct {
    name: []const u8,
    content: []const u8,
    expected_tokens: []const Token,
    ignore_whitespace: bool = false,

    const Failure = struct {
        idx: usize,
        expected: Token,
        got: Token,

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print(
                \\ --- Failure at Token {d} ---
                \\ expected: {f}
                \\ got: {f}
            , .{ self.idx, self.expected, self.got });
        }
    };

    fn runTest(self: @This()) anyerror!?Failure {
        var lexer = Lexer.init(self.content[0..]);
        defer lexer.deinit();
        var i: usize = 0;
        var tok = lexer.nextToken();
        while (tok.type != .eof) : (tok = lexer.nextToken()) {
            if (self.ignore_whitespace) {
                if (tok.type.isWhitespace()) continue;
            }
            if (!self.expected_tokens[i].eql(tok)) {
                return .{
                    .idx = i,
                    .expected = self.expected_tokens[i],
                    .got = tok,
                };
            }
            i += 1;
        }
        return null;
    }
};

fn lexerTest() !void {
    var failed = false;
    for (ALL_CASES) |case| {
        if (case.runTest() catch |e| {
            std.log.err(
                \\ {s}{s} Test Exited Early: {s}{s}
            , .{ shared.ansi.YELLOW, case.name, @errorName(e), shared.ansi.RESET });
            failed = true;
            continue;
        }) |failure| {
            std.log.err(
                \\
                \\ {s}{s} Test Failure:{s}
                \\ {f}
                \\
            , .{ shared.ansi.YELLOW, case.name, shared.ansi.RESET, failure });
        } else {
            std.log.warn(
                \\{s}'{s}' Case Passed!{s}
            , .{ shared.ansi.GREEN, case.name, shared.ansi.RESET });
        }
    }

    if (failed) return error.Failure;
}

const ALL_CASES = &[_]LexerTestCase{
    .{
        .name = "if statements",
        .content =
        \\ ||zz if .something > 34 zz||
        \\ {|.nested_field|}
        \\ ||zz if .nested_thing == 0 zz||
        \\ if {|.|} 
        \\ ||zz else zz||
        \\ ||zz endif zz||
        \\
        \\ ||zz else zz||
        \\ ||zz endif zz||
        ,
        .ignore_whitespace = true,
        .expected_tokens = &[_]Token{
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "if",
                .type = .if_open,
            },
            .{
                .literal = ".something",
                .type = .access,
            },
            .{
                .literal = ">",
                .type = .greater_than,
            },
            .{
                .literal = "34",
                .type = .literal,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".nested_field",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "if",
                .type = .if_open,
            },
            .{
                .literal = ".nested_thing",
                .type = .access,
            },
            .{
                .literal = "==",
                .type = .equal_to,
            },
            .{
                .literal = "0",
                .type = .literal,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "if",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "else",
                .type = .@"else",
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "endif",
                .type = .if_close,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "else",
                .type = .@"else",
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = "endif",
                .type = .if_close,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "",
                .type = .eof,
            },
        },
    },

    .{
        .name = "small case",
        .content =
        \\ Hello {|.field|}!
        \\ ||zz if .field == 'some value' zz||
        \\ ||zz endif zz||
        ,
        .expected_tokens = &[_]Token{
            .{ .literal = " ", .type = .space },
            .{ .literal = "Hello", .type = .literal },
            .{ .literal = " ", .type = .space },
            .{ .literal = "{|", .type = .expression_open },
            .{ .literal = ".field", .type = .access },
            .{ .literal = "|}", .type = .expression_close },
            .{ .literal = "!", .type = .literal },
            .{ .literal = "\n", .type = .newline },
            .{ .literal = " ", .type = .space },
            .{ .literal = "||zz", .type = .statement_open },
            .{ .literal = " ", .type = .space },
            .{ .literal = "if", .type = .if_open },
            .{ .literal = " ", .type = .space },
            .{ .literal = ".field", .type = .access },
            .{ .literal = " ", .type = .space },
            .{ .literal = "==", .type = .equal_to },
            .{ .literal = " ", .type = .space },
            .{ .literal = "\'", .type = .string_wrapper },
            .{ .literal = "some value", .type = .literal },
            .{ .literal = "\'", .type = .string_wrapper },
            .{ .literal = " ", .type = .space },
            .{ .literal = "zz||", .type = .statement_close },
            .{ .literal = "\n", .type = .newline },
            .{ .literal = " ", .type = .space },
            .{ .literal = "||zz", .type = .statement_open },
            .{ .literal = " ", .type = .space },
            .{ .literal = "endif", .type = .if_close },
            .{ .literal = " ", .type = .space },
            .{ .literal = "zz||", .type = .statement_close },
            .{ .literal = "", .type = .eof },
        },
    },
    .{
        .name = "nested for loop",
        .content =
        \\ ||zz for .array_array_field zz||
        \\ ||zz for . zz||
        \\ {|..|}
        \\ {|.|}
        \\ ||zz endfor zz||
        \\ ||zz endfor zz||
        ,
        .expected_tokens = &[_]Token{
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "for",
                .type = .for_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = ".array_array_field",
                .type = .access,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "for",
                .type = .for_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = ".",
                .type = .access,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = "..",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "endfor",
                .type = .for_close,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "endfor",
                .type = .for_close,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
        },
    },
    .{
        .name = "html",
        .content =
        \\ <div>
        \\  {| .field |}
        \\  <div attribute='{| .attr.sub |}' other="{|.other|}" something_else="{|.something_else|}"></div>
        \\ <p> for too long </p>
        \\ <{|.something|}>
        \\ </{|.something|}>
        \\ ||zz for .field2 zz||
        \\ {|.|}
        \\ ||zz endfor zz||
        ,
        .expected_tokens = &[_]Token{
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "<div>",
                .type = .literal,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = ".field",
                .type = .access,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "<div",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "attribute=\'",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = ".attr.sub",
                .type = .access,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\'",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "other=\"",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".other",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\"",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "something_else=\"",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".something_else",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\"></div>",
                .type = .literal,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "<p>",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "for",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "too",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "long",
                .type = .literal,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "</p>",
                .type = .literal,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "<",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".something",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = ">",
                .type = .literal,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "</",
                .type = .literal,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".something",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = ">",
                .type = .literal,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "for",
                .type = .for_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = ".field2",
                .type = .access,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "{|",
                .type = .expression_open,
            },
            .{
                .literal = ".",
                .type = .access,
            },
            .{
                .literal = "|}",
                .type = .expression_close,
            },
            .{
                .literal = "\n",
                .type = .newline,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "||zz",
                .type = .statement_open,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "endfor",
                .type = .for_close,
            },
            .{
                .literal = " ",
                .type = .space,
            },
            .{
                .literal = "zz||",
                .type = .statement_close,
            },
        },
    },
};
