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
        allocator: std.mem.Allocator,

        const Error = error{InaccessibleType} || std.mem.Allocator.Error;

        pub fn init(ctx: Context, allocator: std.mem.Allocator) Self {
            return .{
                .context = ctx,
                .allocator = allocator,
            };
        }

        /// returns a COPY of the field's value
        fn accessField(
            self: Self,
            comptime fieldname: []const u8,
        ) Error![]u8 {
            const field = @field(self.context, fieldname);
            const Ft = @TypeOf(field);
            switch (Ft) {
                []u8, []const u8 => return try self.allocator.dupe(u8, field),
                ArrayList(u8) => return try self.allocator.dupe(u8, field.items),
                else => return error.InaccesibleType,
            }
        }

        pub fn render(self: *Self) Error![]u8 {
            var buffer = try ArrayList(u8).initCapacity(self.allocator, 1024 * 1024);
            var lexer = Lexer.init(TemplateString[0..]);
            var prev_token: ?Token.Type = null;

            while (try lexer.nextToken(self.allocator)) |token| {
                const dbg = try token.debugStr(self.allocator);
                defer self.allocator.free(dbg);
                switch (token.typ) {
                    .generic => {
                        try buffer.appendSlice(self.allocator, token.literal);
                    },
                    .access => {
                        log.debug("trying lookup: [{s}]\n", .{token.literal[1..]});
                        inline for (ContextInfo.@"struct".fields) |f| {
                            if (std.mem.eql(u8, f.name, token.literal[1..])) {
                                const val = try self.accessField(f.name);
                                log.debug("Lookup successful: {d} bytes\n", .{val.len});
                                defer self.allocator.free(val);
                                try buffer.appendSlice(self.allocator, val);
                                break;
                            }
                        }
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
                            try buffer.append(self.allocator, token.typ.literal().?[0]);
                        }
                    },
                    else => {},
                }
                if (!token.typ.isWhitespace()) {
                    prev_token = token.typ;
                }
                log.debug("buffer updated:\n[{s}]", .{buffer.items});
            }
            log.debug("finished render\n", .{});
            return buffer.toOwnedSlice(self.allocator);
        }
    };
}
