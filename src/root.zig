const std = @import("std");
const render = @import("render.zig");
pub const Template = render.Template;
pub const iterate = @import("iterate.zig");
pub const newiterate = @import("newiterate.zig");
pub const Lexer = @import("Lexer.zig");
pub const Token = @import("Token.zig");

pub const Error = error{
    SyntaxInvalid,
    InvalidNext,
    CannotSerialize,
    CannotIterate,
    NoToken,
} || std.mem.Allocator.Error || std.Io.Writer.Error;
