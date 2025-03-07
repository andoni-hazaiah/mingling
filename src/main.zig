const std = @import("std");
const lib = @import("mingling");

fn splitOptionAndValue(arg: []const u8) struct { option: []const u8, value: ?[]const u8 } {
    if (std.mem.indexOf(u8, arg, "=")) |equals_pos| {
        return .{
            .option = arg[0..equals_pos],
            .value = arg[equals_pos + 1 ..],
        };
    }
    return .{
        .option = arg,
        .value = null,
    };
}

pub fn main() !void {
    const split = splitOptionAndValue("remove=");
    const options = split.option;
    const value = split.value.?;

    std.debug.print("{s}, {s}\n", .{ options, value });
}
