const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;
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
        while (tok.typ != .eof) : (tok = lexer.nextToken()) {
            if (self.ignore_whitespace) {
                if (tok.typ.isWhitespace()) continue;
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
    for (ALL_CASES) |case| {
        if (try case.runTest()) |failure| {
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

const ALL_CASES = &[_]LexerTestCase{
    .{
        .name = "if statements",
        .content =
        \\ ||zz if .something > 34 zz||
        \\ {|.|}
        \\ ||zz if .nested_thing == 0 zz||
        \\ {|.|}
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
                .typ = .statement_open,
            },
            .{
                .literal = "if",
                .typ = .if_open,
            },
            .{
                .literal = ".something",
                .typ = .access,
            },
            .{
                .literal = ">",
                .typ = .greater_than,
            },
            .{
                .literal = "34",
                .typ = .literal,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "{|",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "|}",
                .typ = .expression_close,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = "if",
                .typ = .if_open,
            },
            .{
                .literal = ".nested_thing",
                .typ = .access,
            },
            .{
                .literal = "==",
                .typ = .equal_to,
            },
            .{
                .literal = "0",
                .typ = .literal,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "{|",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "|}",
                .typ = .expression_close,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = "else",
                .typ = .@"else",
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = "endif",
                .typ = .if_close,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = "else",
                .typ = .@"else",
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = "endif",
                .typ = .if_close,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
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
                .typ = .space,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "for",
                .typ = .for_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = ".array_array_field",
                .typ = .access,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
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
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "for",
                .typ = .for_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
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
                .literal = "{|",
                .typ = .expression_open,
            },
            .{
                .literal = "..",
                .typ = .access,
            },
            .{
                .literal = "|}",
                .typ = .expression_close,
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
                .literal = "{|",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "|}",
                .typ = .expression_close,
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
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "endfor",
                .typ = .for_close,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
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
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "endfor",
                .typ = .for_close,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
        },
    },
    .{
        .name = "html",
        .content =
        \\ <div>
        \\  ||zz .field zz||
        \\  <div attribute="||zz .attr.sub zz||"></div>
        \\ <p> for too long </p>
        \\ ||zz for .field2 zz||
        \\ {|.|}
        \\ ||zz endfor zz||
        ,
        .expected_tokens = &[_]Token{
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "<div>",
                .typ = .literal,
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
                .typ = .statement_open,
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
                .typ = .statement_close,
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
                .typ = .literal,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "attribute=\"",
                .typ = .literal,
            },
            .{
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = ".attr.sub",
                .typ = .access,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
            .{
                .literal = "\"></div>",
                .typ = .literal,
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
                .literal = "<p>",
                .typ = .literal,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "for",
                .typ = .literal,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "too",
                .typ = .literal,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "long",
                .typ = .literal,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "</p>",
                .typ = .literal,
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
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "for",
                .typ = .for_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = ".field2",
                .typ = .access,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
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
                .literal = "{|",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "|}",
                .typ = .expression_close,
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
                .literal = "||zz",
                .typ = .statement_open,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "endfor",
                .typ = .for_close,
            },
            .{
                .literal = " ",
                .typ = .space,
            },
            .{
                .literal = "zz||",
                .typ = .statement_close,
            },
        },
    },
};
