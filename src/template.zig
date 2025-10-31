const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = parse.Lexer;
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
    TemplateString: []const u8,
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
            var buffer = try ArrayList(u8).initCapacity(self.allocator, 1024 * 1024);
            var lexer = Lexer.init(TemplateString[0..]);
            try lexer.processInput(self.allocator);

            var current_node: ?*std.DoublyLinkedList.Node = &lexer.head.?.node;

            while (current_node) |n| {
                const t: *parse.Token = @fieldParentPtr("node", n);
                defer self.allocator.destroy(t);
                defer t.*.deinit(self.allocator);
                // defer self.allocator.free(t.content);
                switch (t.typ) {
                    TokenType.Block => {
                        try buffer.appendSlice(self.allocator, t.content);
                    },
                    TokenType.Access => {
                        const lookup = std.mem.trim(u8, t.content, "\n .");
                        std.log.debug("trying lookup: [{s}]\n", .{lookup});

                        inline for (ContextInfo.@"struct".fields) |f| {
                            if (std.mem.eql(u8, f.name, lookup)) {
                                const val = try access_field(f.name, Context, self.allocator, self.context);
                                defer self.allocator.free(val);

                                try buffer.appendSlice(self.allocator, val);
                            }
                        }
                    },
                    else => {},
                }
                current_node = t.node.next;
            }
            std.log.debug("finished render\n", .{});
            return buffer;
        }
    };
}

/// returns a COPY of the field's value
fn access_field(
    comptime fieldname: []const u8,
    comptime T: type,
    allocator: std.mem.Allocator,
    ctx: T,
) ![]u8 {
    const field = @field(ctx, fieldname);
    const FT = @TypeOf(field);
    switch (FT) {
        []u8 => return try allocator.dupe(u8, field),
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
