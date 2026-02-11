const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expect_error = std.testing.expectError;
const expect_equal_strings = std.testing.expectEqualStrings;

const h = @import("headers.zig");
const rl = @import("request_line.zig");
const b = @import("body.zig");

pub const EmptyBody = struct {};

pub const Request = struct {
    request_line: rl.RequestLine,
    headers: h.Headers,
    body_raw: []const u8,
    body_allocator: std.mem.Allocator,

    pub fn parse_body(self: Request, comptime body_type: type) b.ParseBodyError!body_type {
        assert(self.body_raw.len > 0);
        return b.parse(self.body_allocator, body_type, self.body_raw);
    }
};

test "parse_body parses a valid payload" {
    const Payload = struct {
        name: []const u8,
        power_level: u64,
    };

    var headers_buffer: [64]u8 = undefined;
    var headers_fba = std.heap.FixedBufferAllocator.init(&headers_buffer);

    var body_parse_buffer: [128]u8 = undefined;
    var body_parse_fba = std.heap.FixedBufferAllocator.init(&body_parse_buffer);

    const request = Request{
        .request_line = try rl.parse("POST /scouter HTTP/1.1"),
        .headers = h.Headers.init(headers_fba.allocator()),
        .body_raw = "{\"name\":\"goku\",\"power_level\":9000}",
        .body_allocator = body_parse_fba.allocator(),
    };

    const payload = try request.parse_body(Payload);
    try expect_equal_strings("goku", payload.name);
    try expect(payload.power_level == 9000);
}

test "parse_body returns CannotParseBody on invalid json" {
    const Payload = struct {
        name: []const u8,
    };

    var headers_buffer: [64]u8 = undefined;
    var headers_fba = std.heap.FixedBufferAllocator.init(&headers_buffer);

    var body_parse_buffer: [128]u8 = undefined;
    var body_parse_fba = std.heap.FixedBufferAllocator.init(&body_parse_buffer);

    const request = Request{
        .request_line = try rl.parse("POST /scouter HTTP/1.1"),
        .headers = h.Headers.init(headers_fba.allocator()),
        .body_raw = "{\"name\":",
        .body_allocator = body_parse_fba.allocator(),
    };

    try expect_error(error.CannotParseBody, request.parse_body(Payload));
}
