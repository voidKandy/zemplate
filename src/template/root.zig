const std = @import("std");
const root = @import("root");
pub const parse = @import("parse.zig");
const ArrayList = std.ArrayList;
const Lexer = parse.Lexer;
const Tokens = parse.Tokens;
const TokenType = parse.TokenType;

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
    comptime TemplateString: []const u8,
) type {
    const ContextInfo = @typeInfo(Context);

    return struct {
        const Self = @This();
        context: Context,
        allocator: std.mem.Allocator,

        const Error = error{};

        pub fn init(ctx: Context, allocator: std.mem.Allocator) !Self {
            return .{
                .context = ctx,
                .allocator = allocator,
            };
        }

        pub fn render(self: *Self) !ArrayList(u8) {
            var buffer = ArrayList(u8).init(self.allocator);
            var lexer = Lexer.init(TemplateString[0..]);
            var tokens: Tokens = try lexer.process_input(self.allocator);

            while (tokens.pop()) |t| {
                defer self.allocator.destroy(t);
                defer self.allocator.free(t.data.content);
                switch (t.data.typ) {
                    TokenType.Block => {
                        try buffer.appendSlice(t.data.content);
                    },
                    TokenType.Access => {
                        const lookup = std.mem.trim(u8, t.data.content, "\n .");
                        std.log.warn("trying lookup: [{s}]\n", .{lookup});

                        inline for (ContextInfo.Struct.fields) |f| {
                            if (std.mem.eql(u8, f.name, lookup)) {
                                const val = try access_field(f.name, Context, self.allocator, self.context);
                                defer self.allocator.free(val);

                                try buffer.appendSlice(val);
                            }
                        }
                    },
                    else => {},
                }
            }
            return buffer;
        }
    };
}

fn access_field(
    comptime fieldname: []const u8,
    comptime T: type,
    allocator: std.mem.Allocator,
    ctx: T,
) ![]u8 {
    const field = @field(ctx, fieldname);
    const FT = @TypeOf(field);
    switch (FT) {
        []u8 => return field,
        ArrayList(u8) => {
            const copy = try allocator.dupe(u8, field.items);
            return copy;
        },
        []const u8 => {},
        else => {
            return error.InaccesibleType;
        },
    }
    var buf: []u8 = try allocator.alloc(u8, field.len);

    for (field, 0..) |byte, i| {
        buf[i] = byte;
    }
    return buf;
}
