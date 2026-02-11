const std = @import("std");
const expect = std.testing.expect;
const expect_equal_strings = std.testing.expectEqualStrings;
const expect_fmt = std.testing.expectFmt;
const expect_error = std.testing.expectError;

const scheme = @import("scheme.zig");
const host = @import("host.zig");
const port = @import("port.zig");
const path = @import("path.zig");

pub const UrlError = error{InvalidUrl};

pub const Error = UrlError || scheme.SchemeError || host.HostError || port.PortError || path.PathError;

pub const Url = struct {
    scheme: scheme.Scheme,
    host: []const u8,
    port: ?u16,
    path: []const u8,

    pub fn format(self: Url, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.scheme.to_string());
        try writer.writeAll("://");
        try writer.writeAll(self.host);
        if (self.port) |port_exists| {
            try writer.print(":{d}", .{port_exists});
        }
        try writer.writeAll(self.path);
    }
};

pub fn parse(url: []const u8) Error!Url {
    if (url.len == 0) return UrlError.InvalidUrl;
    if (std.mem.count(u8, url, "://") != 1) return UrlError.InvalidUrl;

    var iterator = std.mem.splitSequence(u8, url, "://");
    var slice = iterator.first();

    const parsed_scheme = try scheme.parse(slice);

    slice = if (iterator.next()) |s| s else return UrlError.InvalidUrl;

    const slash_index = if (std.mem.indexOfScalar(u8, slice, '/')) |index| index else return UrlError.InvalidUrl;
    const authority = slice[0..slash_index];
    if (authority.len == 0) return UrlError.InvalidUrl;

    var parsed_port: ?u16 = null;
    const parsed_host = blk: {
        if (authority[0] == '[') {
            const closing_bracket_index = std.mem.indexOfScalar(u8, authority, ']') orelse return UrlError.InvalidUrl;
            const host_slice = authority[0 .. closing_bracket_index + 1];

            if (closing_bracket_index + 1 < authority.len) {
                if (authority[closing_bracket_index + 1] != ':') return UrlError.InvalidUrl;
                const port_slice = authority[(closing_bracket_index + 2)..];
                if (port_slice.len == 0) return UrlError.InvalidUrl;
                parsed_port = try port.parse(port_slice);
            }

            break :blk try host.parse(host_slice);
        }

        if (std.mem.indexOfScalar(u8, authority, ':')) |colon_index| {
            if (colon_index == 0) return UrlError.InvalidUrl;
            const port_slice = authority[(colon_index + 1)..];
            if (port_slice.len == 0) return UrlError.InvalidUrl;
            parsed_port = try port.parse(port_slice);
            break :blk try host.parse(authority[0..colon_index]);
        }

        break :blk try host.parse(authority);
    };

    const parsed_path = try path.parse(slice[slash_index..]);
    return Url{ .scheme = parsed_scheme, .host = parsed_host, .port = parsed_port, .path = parsed_path };
}

test "format" {
    var url = Url{ .scheme = scheme.Scheme.http, .host = try host.parse("hello.com"), .port = 8080, .path = try path.parse("/hello/there") };
    try expect_fmt("http://hello.com:8080/hello/there", "{f}", .{url});

    url = Url{ .scheme = scheme.Scheme.http, .host = try host.parse("hello.com"), .port = null, .path = try path.parse("/hello/there") };
    try expect_fmt("http://hello.com/hello/there", "{f}", .{url});

    url = Url{ .scheme = scheme.Scheme.http, .host = try host.parse("172.16.254.1"), .port = 8080, .path = try path.parse("/hello/there") };
    try expect_fmt("http://172.16.254.1:8080/hello/there", "{f}", .{url});

    url = Url{ .scheme = scheme.Scheme.http, .host = try host.parse("[2002:db8::8a3f:362:7897]"), .port = 8080, .path = try path.parse("/") };
    try expect_fmt("http://[2002:db8::8a3f:362:7897]:8080/", "{f}", .{url});
}

test "parse 1" {
    const url_to_parse = "http://172.16.254.1:8080/hello/there";
    const url = try parse(url_to_parse);
    try expect_equal_strings(url.scheme.to_string(), "http");
    try expect_equal_strings(url.host, "172.16.254.1");
    try expect(url.port.? == 8080);
    try expect_equal_strings(url.path, "/hello/there");
}

test "parse 2" {
    const url_to_parse = "http://172.16.254.1/hello/there";
    const url = try parse(url_to_parse);
    try expect_equal_strings(url.scheme.to_string(), "http");
    try expect_equal_strings(url.host, "172.16.254.1");
    try expect(url.port == null);
    try expect_equal_strings(url.path, "/hello/there");
}

test "parse 3 ipv6 with port" {
    const url_to_parse = "http://[2002:db8::8a3f:362:7897]:8080/";
    const url = try parse(url_to_parse);
    try expect_equal_strings(url.scheme.to_string(), "http");
    try expect_equal_strings(url.host, "[2002:db8::8a3f:362:7897]");
    try expect(url.port.? == 8080);
    try expect_equal_strings(url.path, "/");
}

test "parse 4 ipv6 without port" {
    const url_to_parse = "http://[2002:db8::8a3f:362:7897]/hello/there";
    const url = try parse(url_to_parse);
    try expect_equal_strings(url.scheme.to_string(), "http");
    try expect_equal_strings(url.host, "[2002:db8::8a3f:362:7897]");
    try expect(url.port == null);
    try expect_equal_strings(url.path, "/hello/there");
}
