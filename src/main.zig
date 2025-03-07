const std = @import("std");
// const mingling = @import("mingling");
const tokenizer = @import("tokenizer.zig");

pub fn main() !void {
    // We'd use std.process.args()
    const args = [_][]const u8{
        "program",
        "--output=file.txt",
        "-v",
        "input.txt",
    };

    for (args[1..]) |arg| {
        if (tokenizer.parseOption(arg)) |option| {
            std.debug.print("Option: {s}", .{option.name});
            if (option.value) |value| {
                std.debug.print(" = {s}", .{value});
            }
            std.debug.print("\n", .{});
        } else {
            std.debug.print("Argument: {s}\n", .{arg});
        }
    }
}
