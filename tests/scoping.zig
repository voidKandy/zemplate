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
            const n = zemplate.scope.childScopesKvsCount(Test);
            if (n != 7) {
                std.log.err(
                    \\ Expected 7 got: {d}
                , .{n});
                return error.Failure;
            }
        }
    }.t);
    runTest("produces access functions correctly", accessMapKeysTest);
    // runTest("produces child scopes correctly", childScopesTest);
    // runTest("access functions write correct values", accessFunctionTest);
}

fn accessMapKeysTest() !void {
    var value = makeTestValue();
    const scope = try Scope.init(&value, std.testing.allocator);
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
}

fn childScopesTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var value = makeTestValue();
    const scope = try Scope.init(&value, a);

    // TODO:
    // - lookup ".inner" in scope.child_scopes
    // - call returned GetInnerScopeFunc
    // - assert returned scope has ".string" access

    _ = scope;
}

fn accessFunctionTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var value = makeTestValue();
    const scope = try Scope.init(&value, a);

    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    // TODO:
    // - lookup ".inner.string" in scope.access_map
    // - call WriteAccessFunc
    // - assert written output equals "hello"

    _ = writer;
    _ = scope;
}
