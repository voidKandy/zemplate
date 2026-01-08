const std = @import("std");
const zemplate = @import("zemplate");
const ast = zemplate.ast;
const runTest = @import("shared.zig").runTest;

test "rendering" {
    runTest("Iteration", iterationTest);
}

const allocator = std.testing.allocator;

fn iterationTest() !void {
    const Test = struct {
        string: []const u8,
        with_string: struct { string: []const u8 },
    };
    var w = std.Io.Writer.Allocating.init(allocator);
    var arena = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();

    defer {
        arena.deinit();
        w.deinit();
    }
    const stmt =
        ast.Statement{ .@"for" = ast.ForStatement{
            .access = ast.AccessExpression{ .literal = ".string" },
            .alternatives = null,
            .block = .{
                .body = try a.dupe(ast.Statement, &[_]ast.Statement{
                    .{
                        .expression = try ast.ExpressionStatement.create(a, .{
                            .access = .{ .literal = "." },
                        }),
                    },
                }),
            },
        } };
    zemplate.render_context.renderStatement(
        a,
        &w.writer,
        Test{
            .string = "outer string",
            .with_string = .{
                .string = "inner string",
            },
        },
        stmt,
        .{},
    );

    std.debug.print("{s}", .{w.written()});
}
