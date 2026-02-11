const std = @import("std");
const expect = std.testing.expect;
const expect_equal_strings = std.testing.expectEqualStrings;
const expect_error = std.testing.expectError;
const ip = @import("ip.zig");

pub const HostError = error{
    InvalidHost,
};

pub fn parse(host: []const u8) HostError![]const u8 {
    _ = ip.parse(host) catch {
        if (std.net.isValidHostName(host)) return host else return HostError.InvalidHost;
    };

    return host;
}

test "valid hosts" {
    const host_1 = try parse("hello.com");
    try expect_equal_strings("hello.com", host_1);

    const host_2 = try parse("172.16.254.1");
    try expect_equal_strings("172.16.254.1", host_2);
}

test "invalid hosts" {
    const expected_error = HostError.InvalidHost;
    try expect_error(expected_error, parse("he/llo.com"));
}
