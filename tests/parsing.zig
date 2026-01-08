const std = @import("std");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const print = std.debug.print;
const panic = std.debug.panic;
const shared = @import("shared.zig");
const runTest = shared.runTest;
const Lexer = zemplate.Lexer;
const Parser = zemplate.Parser;
const Token = zemplate.Token;

test "parsing" {
    std.testing.log_level = .warn;
    runTest("PARSING", parserTest);
}

fn parserTest() !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);

    defer arena.deinit();

    const cases = try initCases(arena.allocator());
    var failed = false;

    for (cases) |case| {
        if (case.runTest(arena.allocator()) catch |e| {
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
            failed = true;
        } else {
            std.log.warn(
                \\{s}'{s}' Case Passed!{s}
            , .{ shared.ansi.GREEN, case.name, shared.ansi.RESET });
        }
    }

    if (failed) return error.Failed;
}

const ParserTestCase = struct {
    name: []const u8,
    content: []const u8,
    expected_statements: []ast.Statement,

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
        const program = parser.parseProgram() catch |e| {
            parser.logErrors(std.log.scoped(.parserTest));
            return e;
        };

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

fn initCases(a: std.mem.Allocator) std.mem.Allocator.Error![]ParserTestCase {
    return try a.dupe(ParserTestCase, &[_]ParserTestCase{
        .{
            .name = "if statement with literals",
            .content =
            \\ ||zz if .something zz||
            // \\ <div>
            \\ {|.|}
            // \\ </div>
            // \\ <div attribute="
            \\ {|.subfield|}
            // " </div>
            \\ ||zz endif zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{
                            .access = .{
                                .literal = try a.dupe(u8, ".something"),
                            },
                        }),
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                // .{
                                //     .literal = ast.LiteralStatement{ .content = try a.dupe(u8, " <div>\n") },
                                // },
                                .{
                                    .expression = try ast.ExpressionStatement.create(a, .{
                                        .access = .{
                                            .literal = try a.dupe(u8, "."),
                                        },
                                    }),
                                },
                                // .{
                                //     .literal = ast.LiteralStatement{ .content = try a.dupe(u8, " </div>\n <div attribute=\"") },
                                // },
                                .{
                                    .expression = try ast.ExpressionStatement.create(a, .{
                                        .access = .{
                                            .literal = try a.dupe(u8, ".subfield"),
                                        },
                                    }),
                                },
                                // .{
                                //     .literal = ast.LiteralStatement{ .content = try a.dupe(u8, "\" </div>\n") },
                                // },
                            }),
                        },
                        .alternatives = null,
                    },
                },
            }),
        },

        .{
            .name = "if else-if statement",
            .content =
            \\ ||zz if .something zz||
            \\ {|.|}
            \\ ||zz else if .other_thing zz||
            \\ {|.|}
            \\ ||zz endif zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"if" = .{ .condition = try ast.ExpressionStatement.create(a, .{
                        .access = .{
                            .literal = try a.dupe(u8, ".something"),
                        },
                    }), .block = .{
                        .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                            .{
                                .expression = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, "."),
                                    },
                                }),
                            },
                        }),
                    }, .alternatives = try a.dupe(
                        ast.ElseBlock,
                        &[_]ast.ElseBlock{
                            .{
                                .condition = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, ".other_thing"),
                                    },
                                }),
                                .block = .{
                                    .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                        .{
                                            .expression = try ast.ExpressionStatement.create(a, .{
                                                .access = .{
                                                    .literal = try a.dupe(u8, "."),
                                                },
                                            }),
                                        },
                                    }),
                                },
                            },
                        },
                    ) },
                },
            }),
        },

        .{
            .name = "for statement",
            .content =
            \\ ||zz for .iterable json zz||
            \\ {|.|}
            \\ ||zz endfor zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"for" = .{
                        .access = .{
                            .literal = try a.dupe(u8, ".iterable"),
                            .json = true,
                        },
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                .{
                                    .expression = try ast.ExpressionStatement.create(a, .{
                                        .access = .{
                                            .literal = try a.dupe(u8, "."),
                                        },
                                    }),
                                },
                            }),
                        },
                        .alternatives = null,
                    },
                },
            }),
        },

        .{
            .name = "for else statement",
            .content =
            \\ ||zz for .iterable json zz||
            \\ {|.|}
            \\ ||zz else zz||
            \\ {|.alternative|}
            \\ ||zz endfor zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"for" = .{ .access = .{
                        .literal = try a.dupe(u8, ".iterable"),
                        .json = true,
                    }, .block = .{
                        .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                            .{
                                .expression = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, "."),
                                    },
                                }),
                            },
                        }),
                    }, .alternatives = try a.dupe(
                        ast.ElseBlock,
                        &[_]ast.ElseBlock{
                            .{
                                .condition = null,
                                .block = .{
                                    .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                        .{
                                            .expression = try ast.ExpressionStatement.create(a, .{
                                                .access = .{
                                                    .literal = try a.dupe(u8, ".alternative"),
                                                },
                                            }),
                                        },
                                    }),
                                },
                            },
                        },
                    ) },
                },
            }),
        },

        .{
            .name = "conditional statements",
            .content =
            \\ ||zz if .something > 20 zz||
            \\ ||zz endif zz||
            \\ ||zz if .something == 50 zz||
            \\ ||zz endif zz||
            \\ ||zz if .something == .other_thing zz||
            \\ ||zz endif zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{
                            .comparison = .{
                                .operator = .greater_than,
                                .left = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, ".something"),
                                    },
                                }),
                                .right = try ast.ExpressionStatement.create(a, .{
                                    .literal = .{ .integer = 20 },
                                }),
                            },
                        }),
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{}),
                        },
                        .alternatives = null,
                    },
                },
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{
                            .comparison = .{
                                .operator = .equal_to,
                                .left = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, ".something"),
                                    },
                                }),
                                .right = try ast.ExpressionStatement.create(a, .{
                                    .literal = .{ .integer = 50 },
                                }),
                            },
                        }),
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{}),
                        },
                        .alternatives = null,
                    },
                },
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{
                            .comparison = .{
                                .operator = .equal_to,
                                .left = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, ".something"),
                                    },
                                }),
                                .right = try ast.ExpressionStatement.create(a, .{
                                    .access = .{
                                        .literal = try a.dupe(u8, ".other_thing"),
                                    },
                                }),
                            },
                        }),
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{}),
                        },
                        .alternatives = null,
                    },
                },
            }),
        },
        .{
            .name = "nested if statement",
            .content =
            \\ ||zz if .outer zz||
            \\ {|.|}
            \\ ||zz if .inner zz||
            \\ {|.|}
            \\ ||zz endif zz||
            \\ ||zz endif zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"if" = .{
                        .condition = try ast.ExpressionStatement.create(a, .{
                            .access = .{
                                .literal = try a.dupe(u8, ".outer"),
                            },
                        }),
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                .{
                                    .expression = try ast.ExpressionStatement.create(a, .{
                                        .access = .{
                                            .literal = try a.dupe(u8, "."),
                                        },
                                    }),
                                },
                                .{
                                    .@"if" = .{
                                        .condition = try ast.ExpressionStatement.create(a, .{
                                            .access = .{
                                                .literal = try a.dupe(u8, ".inner"),
                                            },
                                        }),
                                        .block = .{
                                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                                .{
                                                    .expression = try ast.ExpressionStatement.create(a, .{
                                                        .access = .{
                                                            .literal = try a.dupe(u8, "."),
                                                        },
                                                    }),
                                                },
                                            }),
                                        },
                                        .alternatives = null,
                                    },
                                },
                            }),
                        },
                        .alternatives = null,
                    },
                },
            }),
        },

        .{
            .name = "nested for statement",
            .content =
            \\ ||zz for .outer_iterable zz||
            \\ {|.|}
            \\ ||zz for .inner_iterable zz||
            \\ {|.|}
            \\ ||zz endfor zz||
            \\ ||zz endfor zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"for" = .{
                        .access = .{
                            .literal = try a.dupe(u8, ".outer_iterable"),
                            .json = false,
                        },
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                .{
                                    .expression = try ast.ExpressionStatement.create(a, .{
                                        .access = .{
                                            .literal = try a.dupe(u8, "."),
                                        },
                                    }),
                                },
                                .{
                                    .@"for" = .{
                                        .access = .{
                                            .literal = try a.dupe(u8, ".inner_iterable"),
                                            .json = false,
                                        },
                                        .block = .{
                                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                                .{
                                                    .expression = try ast.ExpressionStatement.create(a, .{
                                                        .access = .{
                                                            .literal = try a.dupe(u8, "."),
                                                        },
                                                    }),
                                                },
                                            }),
                                        },
                                        .alternatives = null,
                                    },
                                },
                            }),
                        },
                        .alternatives = null,
                    },
                },
            }),
        },

        .{
            .name = "nested for with if and multiple elses",
            .content =
            \\ ||zz for .items zz||
            \\ ||zz if .condition zz||
            \\ {|.|}
            \\ ||zz else if .other_condition zz||
            \\ {|.other|}
            \\ ||zz else zz||
            \\ {|.fallback|}
            \\ ||zz endif zz||
            \\ ||zz else zz||
            \\ {|.empty|}
            \\ ||zz endfor zz||
            ,
            .expected_statements = try a.dupe(ast.Statement, &[_]ast.Statement{
                .{
                    .@"for" = .{
                        .access = .{
                            .literal = try a.dupe(u8, ".items"),
                            .json = false,
                        },
                        .block = .{
                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                .{
                                    .@"if" = .{
                                        // IF condition
                                        .condition = try ast.ExpressionStatement.create(a, .{
                                            .access = .{
                                                .literal = try a.dupe(u8, ".condition"),
                                            },
                                        }),
                                        .block = .{
                                            .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                                .{
                                                    .expression = try ast.ExpressionStatement.create(a, .{
                                                        .access = .{
                                                            .literal = try a.dupe(u8, "."),
                                                        },
                                                    }),
                                                },
                                            }),
                                        },
                                        // IF alternatives
                                        .alternatives = try a.dupe(ast.ElseBlock, &[_]ast.ElseBlock{
                                            // else if
                                            .{
                                                .condition = try ast.ExpressionStatement.create(a, .{
                                                    .access = .{
                                                        .literal = try a.dupe(u8, ".other_condition"),
                                                    },
                                                }),
                                                .block = .{
                                                    .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                                        .{
                                                            .expression = try ast.ExpressionStatement.create(a, .{
                                                                .access = .{
                                                                    .literal = try a.dupe(u8, ".other"),
                                                                },
                                                            }),
                                                        },
                                                    }),
                                                },
                                            },
                                            // else
                                            .{
                                                .condition = null,
                                                .block = .{
                                                    .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                                        .{
                                                            .expression = try ast.ExpressionStatement.create(a, .{
                                                                .access = .{
                                                                    .literal = try a.dupe(u8, ".fallback"),
                                                                },
                                                            }),
                                                        },
                                                    }),
                                                },
                                            },
                                        }),
                                    },
                                },
                            }),
                        },
                        // FOR alternatives
                        .alternatives = try a.dupe(ast.ElseBlock, &[_]ast.ElseBlock{
                            .{
                                .condition = null,
                                .block = .{
                                    .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                                        .{
                                            .expression = try ast.ExpressionStatement.create(a, .{
                                                .access = .{
                                                    .literal = try a.dupe(u8, ".empty"),
                                                },
                                            }),
                                        },
                                    }),
                                },
                            },
                        }),
                    },
                },
            }),
        },
    });
}
