const std = @import("std");
const zemplate = @import("zemplate");
const runTest = @import("shared.zig").runTest;

const Scope = zemplate.scope.Scope;

const Inner = struct {
    string: []const u8,
    other: Other,
};

const Other = struct {
    numbers: []const u32,
};

const Test = struct {
    id: i32,
    inner: Inner,
    arr: []const u8,
    others: []const Other,
};

fn makeTestValue() Test {
    return .{
        .id = 123,
        .inner = .{
            .string = "hello",
            .other = Other{ .numbers = &[_]u32{ 42, 64, 59 } },
        },
        .arr = "abc",
        .others = &[_]Other{
            .{ .numbers = &[_]u32{ 2, 4, 6 } },
        },
    };
}

test "scoping" {
    runTest("access map count correct", struct {
        fn t() !void {
            const n =
                zemplate.scope.accessMapKvsCount(Test);
            if (n != 8) {
                std.log.err(
                    \\ Expected 8 got: {d}
                , .{n});
                return error.Failure;
            }
        }
    }.t);
    runTest("child map count correct", struct {
        fn t() !void {
            const n = zemplate.scope.childScopesKvsCount(Test, Test);
            if (n != 6) {
                std.log.err(
                    \\ Expected 6 got: {d}
                , .{n});
                return error.Failure;
            }
        }
    }.t);
    runTest("produces access functions correctly", accessMapKeysTest);
    runTest("produces child scopes correctly", childScopesKeysTest);
    runTest("child scopes work correctly", childScopeFunctionTest);
}

fn accessMapKeysTest() !void {
    var value = makeTestValue();
    const scope = try Scope.init(Test, &value, std.testing.allocator);
    defer scope.deinit(std.testing.allocator);

    const expected_keys = &[_][]const u8{
        ".",
        ".id",
        ".inner",
        ".arr",
        ".others",
        ".inner.string",
        ".inner.other",
        ".inner.other.numbers",
    };

    for (expected_keys) |k| {
        if (scope.access_map.get(k) == null) {
            std.log.err(
                \\ KEY: {s} NOT PRESENT
            , .{k});
            return error.Failure;
        }
    }
    if (scope.access_map.keys().len != expected_keys.len) return error.Failure;
}

fn childScopesKeysTest() !void {
    var value = makeTestValue();
    const scope = try Scope.init(Test, &value, std.testing.allocator);
    defer scope.deinit(std.testing.allocator);

    const expected_keys = &[_][]const u8{
        ".inner",
        ".arr",
        ".others",
        ".inner.string",
        ".inner.other",
        ".inner.other.numbers",
    };

    for (expected_keys) |k| {
        if (scope.child_scopes.get(k) == null) {
            std.log.err(
                \\ KEY: {s} NOT PRESENT
            , .{k});
            return error.Failure;
        }
    }

    if (scope.child_scopes.keys().len != expected_keys.len) return error.Failure;
}

fn childScopeFunctionTest() !void {
    var value = makeTestValue();
    const scope = try Scope.init(Test, &value, std.testing.allocator);
    defer scope.deinit(std.testing.allocator);
    std.log.err(
        \\
        \\OUTER SCOPE:
        \\ {f}
    , .{scope});

    for ([_][]const u8{
        ".inner",
        ".inner.other",
        ".inner.other.numbers",
    }) |n| {
        const getChild = scope.child_scopes.get(n).?;
        const inner_scope = try getChild(std.testing.allocator, scope);
        defer inner_scope.deinit(std.testing.allocator);
        std.log.err(
            \\
            \\INNER '{s}' SCOPE:
            \\ {f}
            \\
        , .{ n, inner_scope });
    }
}
