const std = @import("std");
pub const template = @import("template.zig");
pub const Lexer = @import("Lexer.zig");
pub const Token = @import("Token.zig");

pub const Error = error{
    SyntaxInvalid,
    CannotSerialize,
    CannotIterate,
    NoToken,
} || std.mem.Allocator.Error || std.Io.Writer.Error;
