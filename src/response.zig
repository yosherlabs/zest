const std = @import("std");
const assert = std.debug.assert;
const expectEqualStrings = std.testing.expectEqualStrings;

const h = @import("headers.zig");
const sl = @import("status_line.zig");
const b = @import("body.zig");

pub const EmptyBody = struct {};

pub const Response = struct {
    status_line: sl.StatusLine,
    headers: h.Headers,
    body_raw: []const u8,
    body_allocator: std.mem.Allocator,
    body_stringify_allocator: std.mem.Allocator,

    pub fn stringifyBody(
        self: *Response,
        comptime BodyType: type,
        body: BodyType,
    ) b.StringifyBodyError!void {
        self.body_raw = try b.stringify(self.body_stringify_allocator, BodyType, body);
        assert(self.body_raw.len > 0);
    }
};

test "stringify body uses stringify allocator" {
    const Payload = struct {
        message: []const u8,
    };

    var headers_buffer: [64]u8 = undefined;
    var headers_fba = std.heap.FixedBufferAllocator.init(&headers_buffer);
    const headers = h.Headers.init(headers_fba.allocator());

    var tiny_body_buffer: [1]u8 = undefined;
    var tiny_body_fba = std.heap.FixedBufferAllocator.init(&tiny_body_buffer);

    var stringify_buffer: [128]u8 = undefined;
    var stringify_fba = std.heap.FixedBufferAllocator.init(&stringify_buffer);

    var response = Response{
        .status_line = try sl.parse("HTTP/1.1 200"),
        .headers = headers,
        .body_raw = "{}",
        .body_allocator = tiny_body_fba.allocator(),
        .body_stringify_allocator = stringify_fba.allocator(),
    };

    try response.stringifyBody(Payload, .{ .message = "hello" });
    try expectEqualStrings("{\"message\":\"hello\"}", response.body_raw);
}
