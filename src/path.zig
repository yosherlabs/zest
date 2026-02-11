const std = @import("std");
const expect = std.testing.expect;
const expect_equal_strings = std.testing.expectEqualStrings;
const expect_error = std.testing.expectError;

pub const PathError = error{
    InvalidPath,
};

pub fn parse(path: []const u8) PathError![]const u8 {
    if (path.len == 0) return PathError.InvalidPath;
    if (path[0] != '/') return PathError.InvalidPath;
    if (path.len > 1 and path[path.len - 1] == '/') return PathError.InvalidPath;

    for (path) |char| {
        if (!is_unreserved(char) and char != '/') return PathError.InvalidPath;
    }
    return path;
}

fn is_unreserved(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or switch (char) {
        '-', '.', '_', '~' => true,
        else => false,
    };
}

test "valid paths" {
    try expect_equal_strings(try parse("/"), "/");
    try expect_equal_strings(try parse("/hello"), "/hello");
    try expect_equal_strings(try parse("/heLLo-1/there.9_kj~"), "/heLLo-1/there.9_kj~");
}

test "invalid paths" {
    const expected_error = PathError.InvalidPath;
    try expect_error(expected_error, parse("//"));
    try expect_error(expected_error, parse("/hi/"));
    try expect_error(expected_error, parse(""));
    try expect_error(expected_error, parse("/he /d"));
}
