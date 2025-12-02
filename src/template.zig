const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const log = std.log.scoped(.template);

const SerializeOptions = struct { field_name: []const u8, json: ?*const std.json.Stringify.Options = null };
const Error = error{ SyntaxInvalid, CannotSerialize } || std.mem.Allocator.Error || std.Io.Writer.Error;

pub fn renderGeneric(a: std.mem.Allocator, some: anytype, template_str: []u8) []u8 {
    var writer = std.Io.Writer.Allocating.init(a);
    _ = &writer;
    _ = some;
    _ = template_str;
}

pub fn render(a: std.mem.Allocator, context: anytype, template_string: []const u8, json_opts: std.json.Stringify.Options) Error![]u8 {
    var out: std.io.Writer.Allocating = .init(a);
    defer out.deinit();
    var lexer = Lexer.init(template_string[0..]);
    var prev_token: ?Token.Type = null;
    var current_access: ?SerializeOptions = null;

    while (try lexer.nextToken(a)) |token| {
        const dbg = try token.debugStr(a);
        defer a.free(dbg);
        switch (token.typ) {
            .generic => {
                try out.writer.writeAll(token.literal);
            },
            .access => {
                if (current_access) |_| return error.SyntaxInvalid;
                current_access = .{ .field_name = token.literal[1..] };
            },
            .json => {
                if (current_access == null)
                    return error.SyntaxInvalid;

                current_access.?.json = &json_opts;
                log.debug("current: {any}", .{current_access.?});
            },
            .marker_close => {
                if (current_access) |opts|
                    try serializeField(context, &out.writer, opts);
                current_access = null;
            },
            .newline, .space => {
                if (should_append: {
                    const t = prev_token orelse break :should_append true;
                    break :should_append switch (t) {
                        // whitespace within marker_open & marker_close should be ignored
                        .access, .json, .marker_open => false,
                        else => true,
                    };
                }) {
                    try out.writer.writeByte(token.typ.literal().?[0]);
                }
            },
            else => {},
        }
        if (!token.typ.isWhitespace()) {
            prev_token = token.typ;
        }
        log.debug("buffer updated:\n[{s}]", .{out.written()});
    }
    log.debug("finished render\n", .{});
    return try out.toOwnedSlice();
}

fn asByteSlice(inst: anytype, comptime T: type) ?[]const u8 {
    const info = @typeInfo(T);

    return switch (info) {
        .pointer => |p| switch (p.size) {
            .slice => if (p.child == u8) inst else null,
            .one => asByteSlice(inst.*, p.child), // RECURSE
            else => null,
        },

        .array => |a| if (a.child == u8)
            inst[0..]
        else
            null,

        .array_sentinel => |a| if (a.child == u8 and a.sentinel == 0)
            inst[0.. :0]
        else
            null,

        .@"struct" => blk: {
            if (T == ArrayList(u8))
                break :blk inst.items;

            break :blk null;
        },

        .optional => |o| if (inst) |val|
            asByteSlice(val, o.child) // RECURSE
        else
            null,

        else => null,
    };
}

inline fn writeType(T: type, inst: anytype, writer: *std.Io.Writer, opts: SerializeOptions) Error!void {
    if (@TypeOf(inst) != T) @panic(@typeName(T) ++ " =! " ++ @typeName(@TypeOf(inst)));
    log.debug("Trying writetype: {s}", .{@typeName(T)});

    const info = @typeInfo(T);
    switch (info) {
        .array => |a| {
            if (a.child == u8) {
                return try if (a.sentinel()) |sent|
                    writer.writeAll(inst[0.. :sent])
                else
                    writer.writeAll(inst[0..]);
            }
        },
        .pointer => |ptr| {
            if (ptr.child == u8) {
                switch (ptr.size) {
                    .slice => return try writer.writeAll(inst),
                    .one => return try writeType(ptr.child, inst.*, writer, opts),
                    else => return error.InvalidPointerType,
                }
            }

            if (ptr.size == .one) return try writeType(ptr.child, inst.*, writer, opts);
        },
        .@"struct" => {
            if (T == ArrayList(u8)) return try writer.writeAll(inst.items);
        },
        else => {},
    }

    if (opts.json) |o|
        return try std.json.Stringify.value(inst, o.*, writer);

    return error.CannotSerialize;
}

fn serializeField(
    parent_struct: anytype,
    writer: *std.Io.Writer,
    opts: SerializeOptions,
) Error!void {
    log.debug(
        \\ trying lookup for field: [{s}]
        \\ Options:
        \\ Json: {any}
    , .{ opts.field_name, opts.json });
    switch (@typeInfo(@TypeOf(parent_struct))) {
        .@"struct" => |st| {
            inline for (st.fields) |f| {
                if (std.mem.eql(u8, f.name, opts.field_name)) {
                    const field = @field(parent_struct, f.name);
                    const Ft = @TypeOf(field);

                    writeType(Ft, field, writer, opts) catch |e| {
                        log.err(
                            \\ Error: {any}
                            \\ Field Type: 
                        ++
                            @typeName(Ft), .{e});
                        return e;
                    };
                }
            }
        },
        else => return error.CannotSerialize,
    }
}

// Takes as arguments:
// `Context` - The type to be used for rendering this template
// /// `TemplateString`
// pub fn Template(
//     /// The type to be used to render the template
//     /// + All of it's fields must be one of:
//     ///    - []const u8
//     ///    - []u8
//     ///    - []ArrayList(u8)
//     comptime Context: type,
//     /// This is the content of the template,
//     /// best used in conjuction with `@embedFile`
//     TemplateString: []const u8,
// ) type {
//     return struct {
//         const Self = @This();
//         context: Context,

//         pub fn init(ctx: Context) Self {
//             return .{
//                 .context = ctx,
//             };
//         }

//         /// Opts might need to be a struct rather than just for json
//         pub fn render(self: *Self, a: std.mem.Allocator, json_opts: std.json.Stringify.Options) Error![]u8 {
//             render(a: Allocator, context: anytype, template_string: []u8, json_opts: Options)
//         }
//     };
// }
