const std = @import("std");

pub const TokenType = enum {
    command, // The program name or a subcommand
    short_option, // A short option (-v)
    long_option, // A long option (--verbose)
    option_value, // A value for an option (the "file.txt" in "--output file.txt")
    positional_arg, // A positional argument
    end_of_options, // The "--" marker
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,

    pub fn init(token_type: TokenType, value: []const u8) Token {
        return Token{
            .type = token_type,
            .value = value,
        };
    }
};

pub const Tokenizer = struct {
    args: []const []const u8,
    index: usize,
    in_option_value: ?[]const u8, // Are we expecting an option value next? This is the actual value we're expecting
    current_option: ?[]const u8, // The option that's expecting a value
    done_with_options: bool, // Have we seen '--' already?
    cluster_index: ?usize, // Index into th current option cluster

    pub fn init(args: []const []const u8) Tokenizer {
        return Tokenizer{
            .args = args,
            .index = 0,
            .in_option_value = null,
            .current_option = null,
            .done_with_options = false,
            .cluster_index = null,
        };
    }

    /// Get the next token from the input.
    pub fn next(self: *Tokenizer) ?Token {

        // If we're in the middle of a cluster, continue from where we left off
        if (self.cluster_index) |cluster_idx| {
            const arg = self.args[self.index]; // The current `arg`
            const option_chars = arg[1..];

            if (cluster_idx < option_chars.len) {
                // Process the next character in the cluster
                const option_char = option_chars[cluster_idx .. cluster_idx + 1];
                // self.cluster_index = if (cluster_idx + 1 < option_chars.len) cluster_idx + 1 else null;

                self.cluster_index.? += 1;

                return Token.init(.short_option, option_char);
            } else {
                // We've processed the entire cluster
                self.cluster_index = null;
                self.index += 1;

                // Peek the following token
                const tok = try self.peek();
                // Check if it is `positional_arg` hanging around
                if (tok != null and tok.?.type == .positional_arg) {
                    // Store it as `option_value` as it might belong to the last cluster option
                    // We should also check for -m 'text' command
                    self.in_option_value = tok.?.value;
                }
            }
        }

        // If we're done, return null
        if (self.index >= self.args.len) {
            return null;
        }

        const arg = self.args[self.index];
        self.index += 1;

        // If we're expecting an option value, return it as such
        if (self.in_option_value) |value| {
            self.in_option_value = null; // Value already retrieved, clear it
            self.current_option = null; // Current option no longer needed, clear it
            return Token.init(.option_value, value);
        }

        // If we've seen `--`, everything after is treated as positional argument or operands
        if (self.done_with_options) {
            return Token.init(.positional_arg, arg);
        }

        // Check for the end of option, `--`, marker.
        if (std.mem.eql(u8, arg, "--")) {
            self.done_with_options = true;
            return Token.init(.end_of_options, arg);
        }

        // Check for `--option=value`
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            if (std.mem.indexOf(u8, arg, "=")) |equals_pos| {
                // This is a long option with a value
                const option_name = arg[2..equals_pos];
                const value = arg[equals_pos + 1 ..];

                // First return the option
                // We'll need to remember the value to return next
                self.index -= 1; // Back up so we can process the same arg again
                self.in_option_value = value; // Store the value for the next iteraction to recover it
                self.current_option = option_name;
                return Token.init(.long_option, option_name);
            } else {
                // This is a long option without a value
                const option_name = arg[2..];
                return Token.init(.long_option, option_name);
            }
        }

        // Check for `-o` or `-o value` or `-abc`
        if (arg.len > 1 and arg[0] == '-' and (arg[1] < '0' or arg[1] > '9')) {
            // This is a short option or option cluster
            if (arg.len == 2) {
                // Simple -o style option
                const option_name = arg[1..];
                return Token.init(.short_option, option_name);
            } else if (std.mem.indexOf(u8, arg, "=")) |equals_pos| {
                // `-o=value` style
                const option_name = arg[1..equals_pos];
                const value = arg[equals_pos + 1 ..];

                if (option_name.len == 1) {
                    // Single short option with equals
                    self.index -= 1; // Back up
                    self.in_option_value = value;
                    self.current_option = option_name;
                    return Token.init(.short_option, option_name);
                } else {
                    // Option cluster with equals is not standard
                    // Let's treat the whole this as a short option
                    return Token.init(.short_option, option_name);
                }
            } else {
                // Option cluster or short option with adjacent value
                const option_chars = arg[1..];

                if (option_chars.len > 1) {
                    // This is an option cluster, handle the first character now
                    // and remember where we are in the cluster for the next time
                    self.cluster_index = 1; // Start with the second character next time
                    self.index -= 1; // Back up so we process the same arg again
                    return Token.init(.short_option, option_chars[0..1]);
                } else {
                    // Simple single short option
                    return Token.init(.short_option, option_chars);
                }
            }
        }

        // If this is the first argument, it's the command
        if (self.index == 1 and !self.done_with_options) {
            return Token.init(.command, arg);
        }

        // Otherwise, it's a positional argument
        return Token.init(.positional_arg, arg);
    }

    /// Peek at the next token without advancidng.
    pub fn peek(self: *Tokenizer) !?Token {
        // Save the current state
        const saved_index = self.index;
        const saved_in_option_value = self.in_option_value;
        const saved_current_option = self.current_option;
        const saved_done_with_options = self.done_with_options;

        // Get the next token
        const token = self.next();

        // Restore the state
        self.index = saved_index;
        self.in_option_value = saved_in_option_value;
        self.current_option = saved_current_option;
        self.done_with_options = saved_done_with_options;

        return token;
    }

    /// Reset the tokenizer to the beginning.
    pub fn reset(self: *Tokenizer) void {
        self.index = 0;
        self.in_option_value = null;
        self.current_option = null;
        self.done_with_options = false;
    }
};

test "tokenizer with simple command" {
    const args = [_][]const u8{"program"};
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with subcommand" {
    const args = [_][]const u8{ "git", "commit" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("git", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token2.type);
    try std.testing.expectEqualStrings("commit", token2.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with long option" {
    const args = [_][]const u8{ "program", "--verbose" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token2.type);
    try std.testing.expectEqualStrings("verbose", token2.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with long option with value" {
    const args = [_][]const u8{ "program", "--output=file.txt" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token2.type);
    try std.testing.expectEqualStrings("output", token2.value);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.option_value, token3.type);
    try std.testing.expectEqualStrings("file.txt", token3.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with short option" {
    const args = [_][]const u8{ "program", "-v" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token2.type);
    try std.testing.expectEqualStrings("v", token2.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with short option cluster" {
    const args = [_][]const u8{ "program", "-abc" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token2.type);
    try std.testing.expectEqualStrings("a", token2.value);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token3.type);
    try std.testing.expectEqualStrings("b", token3.value);

    const token4 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token4.type);
    try std.testing.expectEqualStrings("c", token4.value);
}

test "tokenizer with end of options" {
    const args = [_][]const u8{ "program", "--", "-v" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.end_of_options, token2.type);
    try std.testing.expectEqualStrings("--", token2.value);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token3.type);
    try std.testing.expectEqualStrings("-v", token3.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with mixed arguments" {
    const args = [_][]const u8{ "git", "commit", "-am", "Initial commit", "--verbose", "--", "README.md" };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("git", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token2.type);
    try std.testing.expectEqualStrings("commit", token2.value);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token3.type);
    try std.testing.expectEqualStrings("a", token3.value);

    const token4 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token4.type);
    try std.testing.expectEqualStrings("m", token4.value);

    const token5 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.option_value, token5.type);
    try std.testing.expectEqualStrings("Initial commit", token5.value);

    const token6 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token6.type);
    try std.testing.expectEqualStrings("verbose", token6.value);

    const token7 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.end_of_options, token7.type);
    try std.testing.expectEqualStrings("--", token7.value);

    const token8 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token8.type);
    try std.testing.expectEqualStrings("README.md", token8.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with mixed arguments with cluster without option value" {
    const args = [_][]const u8{
        "utility",
        "subcommand",
        "--verbose",
        "--output=file.txt",
        "-abc",
        "--",
        "-not-an-option",
    };
    var tokenizer = Tokenizer.init(&args);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("utility", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token2.type);
    try std.testing.expectEqualStrings("subcommand", token2.value);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token3.type);
    try std.testing.expectEqualStrings("verbose", token3.value);

    const token4 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token4.type);
    try std.testing.expectEqualStrings("output", token4.value);

    const token5 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.option_value, token5.type);
    try std.testing.expectEqualStrings("file.txt", token5.value);

    const token6 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token6.type);
    try std.testing.expectEqualStrings("a", token6.value);

    const token7 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token7.type);
    try std.testing.expectEqualStrings("b", token7.value);

    const token8 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.short_option, token8.type);
    try std.testing.expectEqualStrings("c", token8.value);

    const token9 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.end_of_options, token9.type);
    try std.testing.expectEqualStrings("--", token9.value);

    const token10 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token10.type);
    try std.testing.expectEqualStrings("-not-an-option", token10.value);

    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with reset" {
    const args = [_][]const u8{ "program", "--verbose" };
    var tokenizer = Tokenizer.init(&args);

    _ = tokenizer.next();
    _ = tokenizer.next();
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());

    tokenizer.reset();

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token2.type);
    try std.testing.expectEqualStrings("verbose", token2.value);
}

test "tokenizer with peek" {
    const args = [_][]const u8{ "program", "--verbose" };
    var tokenizer = Tokenizer.init(&args);

    const peeked1 = try tokenizer.peek() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, peeked1.type);
    try std.testing.expectEqualStrings("program", peeked1.value);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    try std.testing.expectEqualStrings("program", token1.value);

    const peeked2 = try tokenizer.peek() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, peeked2.type);
    try std.testing.expectEqualStrings("verbose", peeked2.value);

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.long_option, token2.type);
    try std.testing.expectEqualStrings("verbose", token2.value);
}

test "tokenizer edge case: empty input" {
    const args = [_][]const u8{};
    var tokenizer = Tokenizer.init(&args);
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer edge case: only command" {
    const args = [_][]const u8{"command"};
    var tokenizer = Tokenizer.init(&args);
    const token = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token.type);
    try std.testing.expectEqualStrings("command", token.value);
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer edge case: command with empty option" {
    const args = [_][]const u8{ "command", "" };
    var tokenizer = Tokenizer.init(&args);
    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.command, token1.type);
    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token2.type);
    try std.testing.expectEqualStrings("", token2.value);
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer edge case: only end of options" {
    const args = [_][]const u8{"--"};
    var tokenizer = Tokenizer.init(&args);
    const token = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.end_of_options, token.type);
    try std.testing.expectEqualStrings("--", token.value);
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer edge case: end of options followed by empty string" {
    const args = [_][]const u8{ "--", "" };
    var tokenizer = Tokenizer.init(&args);
    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.end_of_options, token1.type);
    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(TokenType.positional_arg, token2.type);
    try std.testing.expectEqualStrings("", token2.value);
    try std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "tokenizer with short option cluster and adjacent value" {
    const args = [_][]const u8{ "program", "-xf", "file.txt" };
    var tokenizer = Tokenizer.init(&args);
    _ = tokenizer.next(); // skip command
    const tokenx = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.short_option, tokenx.type);
    try std.testing.expectEqualStrings("x", tokenx.value);
    const tokenf = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.short_option, tokenf.type);
    try std.testing.expectEqualStrings("f", tokenf.value);

    const token_value = tokenizer.next() orelse unreachable;

    try std.testing.expectEqual(.option_value, token_value.type);
    try std.testing.expectEqualStrings("file.txt", token_value.value);
}

test "tokenizer with short option cluster with equals sign (unusual)" {
    const args = [_][]const u8{ "program", "-xf=file.txt" };
    var tokenizer = Tokenizer.init(&args);
    _ = tokenizer.next(); // Skip the command.

    const token_xf = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.short_option, token_xf.type);
    try std.testing.expectEqualStrings("xf", token_xf.value);

    // We treat the ENTIRE "-xf=file.txt" as a short option in this unusual case.
    // try std.testing.expectEqualStrings("xf=file.txt", token_xf.value);
}

test "tokenizer with long option adjacent value after short cluster options" {
    const args = [_][]const u8{ "program", "-am", "test", "--option", "value" };
    var tokenizer = Tokenizer.init(&args);

    _ = tokenizer.next(); // Skip the command

    const token_a = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.short_option, token_a.type);
    try std.testing.expectEqualStrings("a", token_a.value);

    const token_m = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.short_option, token_m.type);
    try std.testing.expectEqualStrings("m", token_m.value);

    const value_am = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.option_value, value_am.type);
    try std.testing.expectEqualStrings("test", value_am.value);

    const token_option = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.long_option, token_option.type);
    try std.testing.expectEqualStrings("option", token_option.value);

    const token_value = tokenizer.next() orelse unreachable;
    try std.testing.expectEqual(.positional_arg, token_value.type);
    // option_value on follows an equal sign
    // try std.testing.expectEqual(.option_value, token_value.type);
    try std.testing.expectEqualStrings("value", token_value.value);
}
