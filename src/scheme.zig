const std = @import("std");
const expect = std.testing.expect;
const expect_error = std.testing.expectError;

pub const SchemeError = error{
    UnsupportedScheme,
};

// https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
pub const Scheme = enum {
    http,

    pub fn to_string(self: Scheme) []const u8 {
        return schemes[@intFromEnum(self)];
    }
};

// https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
pub const schemes = [_][]const u8{"http"};

pub fn parse(scheme: []const u8) SchemeError!Scheme {
    for (schemes, 0..) |v, i| {
        if (std.mem.eql(u8, v, scheme)) {
            return @enumFromInt(i);
        }
    }
    return SchemeError.UnsupportedScheme;
}

test "lengths are equal" {
    const schemes_enum_length = @typeInfo(Scheme).@"enum".fields.len;
    try expect(schemes_enum_length == schemes.len);
}

test "invalid values return an error" {
    const expected_error = SchemeError.UnsupportedScheme;
    try expect_error(expected_error, parse(""));
    try expect_error(expected_error, parse(" "));
    try expect_error(expected_error, parse("HELLO"));
}

test "scheme http" {
    const scheme = Scheme.http;
    try expect(std.mem.eql(u8, scheme.to_string(), "http"));
    const s = try parse("http");
    try expect(s == Scheme.http);
}
