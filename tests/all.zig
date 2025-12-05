const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;

const Lexer = zemplate.Lexer;
const Token = zemplate.Token;

test "custom iterator" {
    const OtherStruct = struct {
        other_string: []const u8,
    };
    const TestStruct = struct {
        other: ?OtherStruct,
        string: []const u8,
        number: u64,

        fn eql(self: @This(), other: @This()) bool {
            return (std.mem.eql(u8, self.string, other.string) and
                (self.other == null and other.other == null or std.mem.eql(u8, self.other.?.other_string, other.other.?.other_string)) and
                self.number == other.number);
        }

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print(
                \\ string: {s}
                \\ number: {d}
                \\ other: {any}
            , .{ self.string, self.number, self.other });
        }
    };
    const expected_strings =
        &[_][]const u8{
            "one",
            "two",
            "three",
        };

    const expected_structs =
        &[_]TestStruct{
            .{
                .string = "alpha zebra",
                .number = 42,
                .other = .{ .other_string = "inner-one" },
            },
            .{
                .string = "moon quartz",
                .number = 987654321,
                .other = .{ .other_string = "inner-two" },
            },
            .{
                .string = "river echo",
                .number = 1337,
                .other = .{ .other_string = "inner-three" },
            },
            .{
                .string = "sky lantern",
                .number = 555555,
                .other = .{ .other_string = "inner-four" },
            },
            .{
                .string = "ghost ember",
                .number = 777777777,
                .other = .{ .other_string = "inner-five" },
            },
        };
    var parent = .{
        .strings = expected_strings,
        .structs = expected_structs,
    };

    {
        var iter = zemplate.iterate.StructFieldIterator(@TypeOf(parent), "strings").fromParentPtr(&parent);
        var i: usize = 0;
        while (iter.next()) |n| : (i += 1) {
            if (!std.mem.eql(u8, n, expected_strings[i])) {
                std.log.err(
                    \\ Expected:
                    \\ {s}
                    \\ Got:
                    \\ {s}
                , .{ expected_strings[i], n });
                @panic("failed");
            }
        }
    }
    {
        var iter = zemplate.iterate.StructFieldIterator(@TypeOf(parent), "structs").fromParentPtr(&parent);
        var i: usize = 0;
        while (iter.next()) |n| : (i += 1) {
            if (!n.eql(expected_structs[i])) {
                std.log.err(
                    \\ Expected:
                    \\ {f}
                    \\ Got:
                    \\ {f}
                , .{ expected_structs[i], n });
                @panic("failed");
            }
        }
    }
    print("ITERATOR Test PASSED", .{});
}

test "lexer test" {
    // std.testing.log_level = .debug;
    const content =
        \\ <div>
        \\  ||zz .field zz||
        \\  <div attribute="||zz .attr.sub zz||"></div>
        \\ <p> for too long </p>
        \\ ||zz for .field2 zz||
        \\ {{.}}
        \\ ||zz endfor zz||
    ;
    const expected = &[_]Token{
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
    };
    var lexer = Lexer.init(content[0..]);
    defer lexer.deinit();
    var i: usize = 0;
    while (try lexer.nextToken()) |next| : (i += 1) {
        if (!expected[i].eql(next)) {
            std.debug.panic(
                \\ Token {d} Expected:
                \\ {f}
                \\ Got:
                \\ {f}
            , .{ i, expected[i], next });
        }
    }
    print(
        \\
        \\ LEXER Test PASSED
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

    var tmpl = TestTmpl.init(
        .{ .field = "World" },
    );
    const render = try tmpl.render(
        allocator,
        \\ Hello ||zz .field zz||!
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
        \\ README Test PASSED
    , .{});
}

test "nest test" {
    // std.testing.log_level = .debug;
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello World!
    ;
    const Tmpl = zemplate.Template(struct { field: struct { inner: []const u8 } });
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
    , .{});
}

test "for loop test" {
    // std.testing.log_level = .debug;
    const allocator = std.testing.allocator;
    const expected =
        \\ Hello!
        \\ W
        \\ o
        \\ r
        \\ l
        \\ d
        \\
        \\ one
        \\ two
        \\ three
        \\
        \\ subfield
        \\ subfield2
        \\
        \\
    ;
    const SubType =
        struct { inner_field: []const u8 };
    const Tmpl = zemplate.Template(struct { outer_field: []const u8, array: []const []const u8, structs: []const SubType });
    var tmpl = Tmpl.init(
        .{ .outer_field = "World", .array = &[_][]const u8{
            "one",
            "two",
            "three",
        }, .structs = &[_]SubType{
            .{ .inner_field = "subfield" },
            .{ .inner_field = "subfield2" },
        } },
    );
    const render = try tmpl.render(
        allocator,
        \\ Hello!
        \\||zz for .outer_field zz||
        \\ {{.}}
        \\||zz endfor zz||
        \\||zz for .array zz||
        \\ {{ . }}
        \\||zz endfor zz||
        \\||zz for .structs zz||
        \\ {{ .inner_field }}
        \\||zz endfor zz||
        \\
    ,
        .{},
    );
    defer allocator.free(render);
    logDiff(expected, render);

    // if (!std.mem.eql(u8, expected, render)) {
    //     std.log.err(
    //         \\ did not get expected render!
    //         \\ Expected:
    //         \\ [{s}]
    //         \\ got:
    //         \\ [{s}]
    //         \\
    //     , .{ expected, render });
    // for ([_][]const u8{ expected, render }) |str| {
    //     for (0..str.len) |i| {
    //         std.log.err(
    //             \\[{c}]
    //         , .{str[i]});
    //     }
    //     std.log.err("DONE PRINTING\n", .{});
    // }
    //     return;
    // }
    print(
        \\
        \\ FOR LOOP Test PASSED
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
    , .{});
}

fn logDiff(expected: []const u8, actual: []const u8) void {
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

        // Show fully escaped forms to catch invisible differences
        // std.log.err("Expected escaped: \"{s}\"", .{std.format.fmt(expected)});
        // std.log.err("Actual   escaped: \"{s}\"", .{std.zig.fmtEscapes(actual)});

        return;
    }
}
