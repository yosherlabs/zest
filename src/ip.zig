const std = @import("std");
const expect = std.testing.expect;
const expect_error = std.testing.expectError;
const expect_equal_strings = std.testing.expectEqualStrings;

pub const IpError = error{
    InvalidIpAddress,
};

pub fn parse(ip: []const u8) IpError![]const u8 {
    if (valid_ip4(ip) or valid_ip6(ip)) return ip else return IpError.InvalidIpAddress;
}

fn valid_ip4(ip: []const u8) bool {
    _ = std.net.Address.parseIp4(ip, 0) catch return false;
    return true;
}

fn valid_ip6(ip: []const u8) bool {
    if (ip.len >= 3 and ip[0] == '[' and ip[ip.len - 1] == ']') {
        _ = std.net.Address.parseIp6(ip[1 .. ip.len - 1], 0) catch return false;
        return true;
    } else return false;
}

test "valid ipv4 addresses" {
    const result = try parse("172.16.254.1");
    try expect_equal_strings("172.16.254.1", result);
}

test "valid ipv6 addresses" {
    const result = try parse("[2002:db8::8a3f:362:7897]");
    try expect_equal_strings("[2002:db8::8a3f:362:7897]", result);
}

test "invalid ipv4 addresses" {
    const expected_error = IpError.InvalidIpAddress;
    try expect_error(expected_error, parse("172.16.256.1"));
}

test "invalid ipv6 addresses" {
    const expected_error = IpError.InvalidIpAddress;
    try expect_error(expected_error, parse("[56FE::2159:5BBC::6594]"));
}
