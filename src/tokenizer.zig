const std = @import("std");

pub const OptionStyle = enum {
    no_value, // e.g., --verbose
    equals_value, // e.g., --output=file.txt
    space_value, // e.g., --output file.txt
};

pub const OptionResult = struct {
    name: []const u8,
    value: ?[]const u8,
    style: OptionStyle,
};

pub fn parseOption(arg: []const u8) ?OptionResult {
    // Check if this looks like an option
    if (arg.len < 2 or arg[0] != '-') {
        return null;
    }

    // Determine if it's a long option (--option) or short option (-o)
    const is_long = arg.len > 2 and arg[1] == '-';
    const name_start: usize = if (is_long) 2 else 1;

    // Check for equals sign
    if (std.mem.indexOf(u8, arg, "=")) |equals_pos| {
        // Option has a value after equals
        const name = arg[name_start..equals_pos];
        const value = arg[equals_pos + 1 ..];
        return OptionResult{
            .name = name,
            .value = value,
            .style = .equals_value,
        };
    }

    // No equal sign, it's a flag or an option tha takes a separate value
    return OptionResult{
        .name = arg[name_start..],
        .value = null,
        .style = .no_value,
    };
}

test "parseOption with long option" {
    const result = parseOption("--output=file.txt") orelse unreachable;
    try std.testing.expectEqualStrings("output", result.name);
    try std.testing.expectEqualStrings("file.txt", result.value.?);
    try std.testing.expectEqual(OptionStyle.equals_value, result.style);
}

test "parseOption with short option" {
    const result = parseOption("-o=file.txt") orelse unreachable;
    try std.testing.expectEqualStrings("o", result.name);
    try std.testing.expectEqualStrings("file.txt", result.value.?);
    try std.testing.expectEqual(OptionStyle.equals_value, result.style);
}

test "parseOption with flag" {
    const result = parseOption("--verbose") orelse unreachable;
    try std.testing.expectEqualStrings("verbose", result.name);
    try std.testing.expectEqual(null, result.value);
    try std.testing.expectEqual(OptionStyle.no_value, result.style);
}

test "parseOption with non-option" {
    const result = parseOption("filename.txt");
    try std.testing.expectEqual(null, result);
}
