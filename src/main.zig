const std = @import("std");
// const mingling = @import("mingling");
const tokenizer = @import("tokenizer.zig");
const Tokenizer = tokenizer.Tokenizer;
const TokenType = tokenizer.TokenType;

// set disassembly-flavor intel

pub fn main() !void {
    // We'd use std.process.args()
    const args = [_][]const u8{
        "myapp",
        "subcommand",
        "--verbose",
        "--output=file.txt",
        "-abc",
        "--",
        "-not-an-option",
    };

    var tknizer = Tokenizer.init(&args);

    std.debug.print("Tokens:\n", .{});
    while (tknizer.next()) |token| {
        std.debug.print(" {s}: {s}\n", .{ @tagName(token.type), token.value });
    }
}
