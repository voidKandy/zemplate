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

pub const ansi = struct {
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

pub const Failure = struct {
    index: usize,
    start: usize,
    exp_end: usize,
    got_end: usize,
    exp_ctx: []const u8,
    got_ctx: []const u8,
    expected: []u8,
    got: []u8,

    const CONTEXT_SIZE = 10;
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            \\ Render mismatch at index {d}
        , .{self.index});
        try writer.print(
            \\ Expected context ({}..{}): "{s}"
        , .{
            self.start,
            self.exp_end,
            self.exp_ctx,
        });
        try writer.print(
            \\ Actual   context ({}..{}): "{s}"
        , .{
            self.start,
            self.got_end,
            self.got_ctx,
        });
        if (self.index < self.expected.len)
            try writer.print(
                \\ Expected char: '{c}' (byte {d})
            , .{
                self.expected[self.index],
                self.expected[self.index],
            })
        else
            try writer.writeAll("Given index is too large for expected content\n");

        if (self.index < self.got.len)
            try writer.print(
                \\ Actual   char: '{c}' (byte {d})
            , .{
                self.got[self.index],
                self.got[self.index],
            })
        else
            try writer.writeAll("Given index is too large for got content\n");
    }

    pub fn checkForFailure(a: std.mem.Allocator, got: []const u8, expected: []const u8) ?Failure {
        const idx = std.mem.indexOfDiff(u8, expected, got) orelse return null;
        const start = @max(idx, @as(usize, Failure.CONTEXT_SIZE)) - Failure.CONTEXT_SIZE;
        const end_expected = @min(expected.len, idx + Failure.CONTEXT_SIZE);
        const end_actual = @min(got.len, idx + Failure.CONTEXT_SIZE);
        const my_got = a.dupe(u8, got) catch @panic("out of memory");
        const my_expected = a.dupe(u8, expected) catch @panic("out of memory");

        const exp_ctx = my_expected[start..end_expected];
        const act_ctx = my_got[start..end_actual];
        return .{
            .index = idx,
            .start = start,
            .exp_end = end_expected,
            .got_end = end_actual,
            .exp_ctx = exp_ctx,
            .got_ctx = act_ctx,
            .expected = my_expected,
            .got = my_got,
        };
    }

    pub fn deinit(self: *@This(), a: std.mem.Allocator) void {
        a.free(self.got);
        a.free(self.expected);
    }
};
