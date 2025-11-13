const std = @import("std");
const root = @import("root.zig");
pub const parse = root.parse;
const ArrayList = std.ArrayList;
const Lexer = parse.Lexer;
const TokenType = parse.TokenType;
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

        pub fn render(self: *Self) Error!ArrayList(u8) {
            var buffer = try ArrayList(u8).initCapacity(self.allocator, 1024 * 1024);
            var lexer = Lexer.init(TemplateString[0..]);
            try lexer.processInput(self.allocator);

            var current_node: ?*std.DoublyLinkedList.Node = &lexer.head.?.node;

            while (current_node) |n| {
                const t: *parse.Token = @fieldParentPtr("node", n);
                defer self.allocator.destroy(t);
                defer t.*.deinit(self.allocator);
                switch (t.typ) {
                    TokenType.Block => {
                        try buffer.appendSlice(self.allocator, t.content);
                    },
                    TokenType.Access => {
                        const lookup = std.mem.trim(u8, t.content, "\n .");
                        log.debug("trying lookup: [{s}]\n", .{lookup});

                        inline for (ContextInfo.@"struct".fields) |f| {
                            if (std.mem.eql(u8, f.name, lookup)) {
                                const val = try self.accessField(f.name);
                                log.debug("Lookup successful: {d} bytes\n", .{val.len});
                                defer self.allocator.free(val);

                                try buffer.appendSlice(self.allocator, val);
                            }
                        }
                    },
                    else => {},
                }
                current_node = t.node.next;
            }
            log.debug("finished render\n", .{});
            return buffer;
        }
    };
}
