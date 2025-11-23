const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const log = std.log.scoped(.template);

/// Takes as arguments:
/// `Context` - The type to be used for rendering this template
/// `TemplateString`
pub fn Template(
    /// The type to be used to render the template
    /// + All of it's fields must be one of:
    ///    - []const u8
    ///    - []u8
    ///    - []ArrayList(u8)
    comptime Context: type,
    /// This is the content of the template,
    /// best used in conjuction with `@embedFile`
    TemplateString: []const u8,
) type {
    const ContextInfo = @typeInfo(Context);

    return struct {
        const Self = @This();
        context: Context,

        const Error = error{ SyntaxInvalid, CannotSerialize } || std.mem.Allocator.Error || std.Io.Writer.Error;

        pub fn init(ctx: Context) Self {
            return .{
                .context = ctx,
            };
        }

        const SerializeOptions = struct { field_name: []const u8, json: ?*const std.json.Stringify.Options = null };

        /// Serializes field of Context according to the options passed & writes it to the writer
        fn serializeField(
            self: Self,
            writer: *std.Io.Writer,
            opts: SerializeOptions,
        ) Error!void {
            log.debug(
                \\ trying lookup for field: [{s}]
                \\ Options:
                \\ Json: {any}
            , .{ opts.field_name, opts.json });
            inline for (ContextInfo.@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, opts.field_name)) {
                    const field = @field(self.context, f.name);
                    const Ft = @TypeOf(field);
                    switch (Ft) {
                        []u8, []const u8, ArrayList(u8) => {
                            try if (Ft == ArrayList(u8))
                                writer.writeAll(field.items)
                            else
                                writer.writeAll(field);

                            return;
                        },
                        else => {},
                    }

                    if (opts.json) |o| {
                        try switch (@typeInfo(Ft)) {
                            .pointer => std.json.Stringify.value(field.*, o.*, writer),
                            else => std.json.Stringify.value(field, o.*, writer),
                        };
                        return;
                    }
                    return error.CannotSerialize;
                }
            }
        }
        /// Opts might need to be a struct rather than just for json
        pub fn render(self: *Self, a: std.mem.Allocator, json_opts: std.json.Stringify.Options) Error![]u8 {
            var out: std.io.Writer.Allocating = .init(a);
            defer out.deinit();
            // var buffer = try ArrayList(u8).initCapacity(a, 1024 * 1024);
            var lexer = Lexer.init(TemplateString[0..]);
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
                            try self.serializeField(&out.writer, opts);
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
    };
}
