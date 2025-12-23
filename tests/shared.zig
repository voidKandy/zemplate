const std = @import("std");

pub fn runTest(comptime name: []const u8, run_fn: anytype) void {
    const log = std.log.scoped(.TestRunner);
    log.warn(
        \\ {s}'{s}' Test {s}STARTING {s}
        \\
    , .{ ansi.BLUE, name, ansi.BOLD, ansi.RESET });

    run_fn() catch |e| {
        log.err(
            \\ {s}'{s}' Test {s}FAILED{s} 
            \\
        , .{ ansi.RED, name, ansi.BOLD, ansi.RESET });
        @panic(@errorName(e));
    };

    log.warn(
        \\ {s}'{s}' Test {s}PASSED{s}
        \\
    , .{ ansi.GREEN, name, ansi.BOLD, ansi.RESET });
}

const ansi = struct {
    pub const RESET = "\x1b[0m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const BOLD = "\x1b[1m";
};

pub fn logDiff(expected: []const u8, actual: []const u8) !void {
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

        return error.DiffExists;
    }
    return;
}
