const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const panic = std.debug.panic;

const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

const LexerTestCase = struct {
    name: []const u8,
    content: []const u8,
    expected_tokens: []const Token,

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
        while (try lexer.nextToken()) |next| : (i += 1) {
            if (!self.expected_tokens[i].eql(next)) {
                return .{
                    .idx = i,
                    .expected = self.expected_tokens[i],
                    .got = next,
                };
            }
        }
        return null;
    }
};

test "lexer test" {
    for (ALL_CASES) |case| {
        if (try case.runTest()) |failure| {
            panic(
                \\
                \\ {s} Test Failed:
                \\ {f}
                \\
            , .{ case.name, failure });
        }
    }
    print(
        \\
        \\ LEXER Test PASSED
        \\
    , .{});
}

const ALL_CASES = &[_]LexerTestCase{
    .{
        .name = "nested for loop",
        .content =
        \\ ||zz for .array_array_field zz||
        \\ ||zz for . zz||
        \\ {{..}}
        \\ {{.}}
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
                .typ = .marker_open,
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
                .literal = "||zz",
                .typ = .marker_open,
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
                .literal = "{{",
                .typ = .expression_open,
            },
            .{
                .literal = "..",
                .typ = .access,
            },
            .{
                .literal = "}}",
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
                .literal = "{{",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "}}",
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
                .typ = .marker_open,
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
                .literal = "||zz",
                .typ = .marker_open,
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
                .typ = .marker_close,
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
        \\ {{.}}
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
                .typ = .marker_open,
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
                .typ = .marker_close,
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
                .typ = .marker_open,
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
                .literal = "{{",
                .typ = .expression_open,
            },
            .{
                .literal = ".",
                .typ = .access,
            },
            .{
                .literal = "}}",
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
                .typ = .marker_open,
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
                .typ = .marker_close,
            },
        },
    },
};
