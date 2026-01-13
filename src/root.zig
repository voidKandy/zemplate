const std = @import("std");
pub const render = @import("render.zig");
pub const ast = @import("ast.zig");
pub const util = @import("util.zig");
pub const scope = @import("scope.zig");
pub const Template = render.Template;
pub const Lexer = @import("Lexer.zig");
pub const Parser = @import("Parser.zig");
pub const Token = @import("Token.zig");

pub const Error = error{
    SyntaxInvalid,
    NotStructType,
    InvalidNext,
    CannotSerialize,
    CannotIterate,
    NoToken,
} || std.mem.Allocator.Error || std.Io.Writer.Error;
