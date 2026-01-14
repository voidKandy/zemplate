const std = @import("std");
const root = @import("root.zig");
const ArrayList = std.ArrayList;
const log = std.log.scoped(.util);
const Error = @import("root.zig").Error;
const JsonOptions = std.json.Stringify.Options;
const comptimePrint = std.fmt.comptimePrint;

const COMPILE_LOGS: bool = false;

pub inline fn compileLogPrint(comptime fmt: []const u8, args: anytype) void {
    if (COMPILE_LOGS) @compileLog(comptimePrint(fmt, args));
}

pub fn Deref(comptime T: type) type {
    switch (@typeInfo(T)) {
        .pointer => |ptr| if (ptr.size == .one) return Deref(ptr.child) else return T,
        else => return T,
    }
}

pub inline fn countPeriods(comptime string: []const u8) usize {
    comptime var i: usize = 0;

    inline for (string) |ch| {
        if (ch == '.') i += 1;
    }

    if (i == 0) @compileError(comptimePrint("counting periods on invalid input: {s}", .{string}));
    return i;
}

pub inline fn periodIdcs(comptime string: []const u8) [countPeriods(string)]usize {
    comptime var idcs: [countPeriods(string)]usize = undefined;
    comptime var i: usize = 0;

    inline for (string, 0..) |ch, k| {
        if (ch == '.') {
            idcs[i] = k;
            i += 1;
        }
    }

    if (i != countPeriods(string)) @compileError(comptimePrint(
        \\ period count of '{s}' does not match indices gotten
        \\ i != {d}
    , .{ string, countPeriods(string) }));

    return idcs;
}

pub inline fn hasField(comptime T: type, comptime name: []const u8) bool {
    if (@typeInfo(T) != .@"struct") return false;
    inline for (@typeInfo(T).@"struct".fields) |f| if (sliceEqualComptime(f.name, name)) return true;

    compileLogPrint("{s} does not have field {s}", .{ @typeName(T), name });
    return false;
}
/// using std.mem.eql on two comptime strings can sometimes return false positives
pub inline fn sliceEqualComptime(comptime a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    inline for (0..a.len) |i| {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub const WriteError = std.Io.Writer.Error || error{InvalidType};

pub inline fn writeType(
    T: type,
    inst: anytype,
    writer: *std.Io.Writer,
    json_opts: JsonOptions,
    print_json: bool,
) WriteError!void {
    if (@TypeOf(inst) != T) @panic(@typeName(T) ++ " =! " ++ @typeName(@TypeOf(inst)));
    log.debug("Trying writetype: {s}", .{@typeName(T)});

    if (print_json) {
        const end_before = writer.end;
        try std.json.Stringify.value(inst, json_opts, writer);
        log.debug("Wrote JSON to writer: {s}", .{writer.buffer[end_before..writer.end]});
        return;
    }

    const info = @typeInfo(T);
    switch (info) {
        .array => |a| {
            log.debug(
                \\ array type
            , .{});
            if (a.child == u8) {
                const bytes =
                    if (a.sentinel()) |sent|
                        inst[0.. :sent]
                    else
                        inst[0..];

                log.debug("Bytes: {s}", .{bytes});
                try writer.writeAll(bytes);
                return;
            }

            log.debug("array child is not u8, got {s}", .{@typeName(a.child)});
        },
        .pointer => |ptr| {
            log.debug(
                \\ pointer type
                \\ size: {any}
            , .{ptr.size});
            if (ptr.child == u8) {
                switch (ptr.size) {
                    .slice => {
                        log.debug("Bytes: {s}", .{inst});
                        try writer.writeAll(inst);

                        return;
                    },
                    .one => return try writeType(ptr.child, inst.*, writer, json_opts, print_json),
                    else => return error.InvalidType,
                }
            }

            log.debug("pointer child is not u8, got {s}", .{@typeName(ptr.child)});

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, json_opts, print_json);
        },
        .@"struct" => |s| {
            log.debug(
                \\ struct type
            , .{});
            if (T == ArrayList(u8)) {
                return try writer.writeAll(inst.items);
            }

            inline for (s.fields) |fe| {
                log.debug(
                    \\ field '{s}' of {s}
                , .{ fe.name, @typeName(T) });
                writeType(fe.type, @field(inst, fe.name), writer, json_opts, print_json) catch |e| {
                    if (e != error.InvalidType) @panic(@errorName(e));
                    log.err(
                        \\ failing field '{s}'
                    , .{fe.name});
                };
            }

            return;
        },
        .int => |int| {
            return try if (int.bits == @bitSizeOf(u8))
                writer.writeByte(inst)
            else
                writer.print("{d}", .{inst});
        },
        else => {},
    }
    log.warn("No branch for handling {s}", .{@typeName(T)});
    return error.InvalidType;
}
