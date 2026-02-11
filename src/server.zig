const std = @import("std");
const assert = std.debug.assert;
const expect_error = std.testing.expectError;
const expect_equal_strings = std.testing.expectEqualStrings;
const log = std.log.scoped(.zest);
const rl = @import("request_line.zig");
const req = @import("request.zig");
const res = @import("response.zig");
const sl = @import("status_line.zig");
const h = @import("headers.zig");
const s = @import("status.zig");
const v = @import("version.zig");
const Router = @import("router.zig").Router;

pub const Config = struct {
    address: std.net.Address,
    max_read_request_line_bytes: usize,
    max_read_request_headers_bytes: usize,
    max_request_headers_map_bytes: usize,
    max_response_headers_map_bytes: usize,
    max_read_request_body_bytes: usize,
    max_request_body_parse_bytes: usize,
    max_response_body_bytes: usize,
    max_response_body_stringify_bytes: usize,
    max_json_validate_bytes: usize,

    pub fn init(address_name: []const u8, address_port: u16, buffer_bytes: usize) !Config {
        return Config{
            .address = try std.net.Address.parseIp(address_name, address_port),
            .max_read_request_line_bytes = buffer_bytes,
            .max_read_request_headers_bytes = buffer_bytes,
            .max_request_headers_map_bytes = buffer_bytes,
            .max_response_headers_map_bytes = buffer_bytes,
            .max_read_request_body_bytes = buffer_bytes,
            .max_request_body_parse_bytes = buffer_bytes,
            .max_response_body_bytes = buffer_bytes,
            .max_response_body_stringify_bytes = buffer_bytes,
            .max_json_validate_bytes = buffer_bytes,
        };
    }
};

pub fn start(comptime config: Config, comptime router: Router) !void {
    comptime {
        assert(config.max_read_request_line_bytes > 0);
        assert(config.max_read_request_headers_bytes > 0);
        assert(config.max_request_headers_map_bytes > 0);
        assert(config.max_response_headers_map_bytes > 0);
        assert(config.max_read_request_body_bytes > 0);
        assert(config.max_request_body_parse_bytes > 0);
        assert(config.max_response_body_bytes > 0);
        assert(config.max_response_body_stringify_bytes > 0);
        assert(config.max_json_validate_bytes > 0);
    }

    var server = try config.address.listen(.{ .reuse_address = true });
    defer server.deinit();

    log.info("listening at {f}", .{config.address});

    var read_request_line_buffer: [config.max_read_request_line_bytes]u8 = undefined;
    var read_request_line_fba = std.heap.FixedBufferAllocator.init(&read_request_line_buffer);

    var read_request_headers_buffer: [config.max_read_request_headers_bytes]u8 = undefined;
    var read_request_headers_fba = std.heap.FixedBufferAllocator.init(&read_request_headers_buffer);

    var request_headers_map_buffer: [config.max_request_headers_map_bytes]u8 = undefined;
    var request_headers_map_fba = std.heap.FixedBufferAllocator.init(&request_headers_map_buffer);

    var response_headers_map_buffer: [config.max_response_headers_map_bytes]u8 = undefined;
    var response_headers_map_fba = std.heap.FixedBufferAllocator.init(&response_headers_map_buffer);

    var read_request_body_buffer: [config.max_read_request_body_bytes]u8 = undefined;
    var read_request_body_fba = std.heap.FixedBufferAllocator.init(&read_request_body_buffer);

    var request_body_parse_buffer: [config.max_request_body_parse_bytes]u8 = undefined;
    var request_body_parse_fba = std.heap.FixedBufferAllocator.init(&request_body_parse_buffer);

    var response_body_buffer: [config.max_response_body_bytes]u8 = undefined;
    var response_body_fba = std.heap.FixedBufferAllocator.init(&response_body_buffer);

    var response_body_stringify_buffer: [config.max_response_body_stringify_bytes]u8 = undefined;
    var response_body_stringify_fba = std.heap.FixedBufferAllocator.init(&response_body_stringify_buffer);

    var json_validate_buffer: [config.max_json_validate_bytes]u8 = undefined;
    var json_validate_fba = std.heap.FixedBufferAllocator.init(&json_validate_buffer);

    accept_loop: while (true) : ({
        read_request_line_fba.reset();
        read_request_headers_fba.reset();
        request_headers_map_fba.reset();
        response_headers_map_fba.reset();
        read_request_body_fba.reset();
        request_body_parse_fba.reset();
        response_body_fba.reset();
        response_body_stringify_fba.reset();
        json_validate_fba.reset();
    }) {
        var connection = server.accept() catch |err| switch (err) {
            error.ConnectionResetByPeer, error.ConnectionAborted => {
                log.err("could not accept connection: '{s}'", .{@errorName(err)});
                continue;
            },
            else => return err,
        };

        const max_read_line_bytes = if (config.max_read_request_line_bytes > config.max_read_request_headers_bytes)
            config.max_read_request_line_bytes
        else
            config.max_read_request_headers_bytes;
        var stream_reader_buffer: [max_read_line_bytes]u8 = undefined;
        var stream_reader = connection.stream.reader(&stream_reader_buffer);
        const r = stream_reader.interface();

        var stream_writer_buffer: [1024]u8 = undefined;
        var stream_writer = connection.stream.writer(&stream_writer_buffer);
        const w = &stream_writer.interface;

        const read_request_line_slice = read_http_line(r) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        const read_request_line_unowned = read_request_line_slice orelse {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        if (read_request_line_unowned.len > config.max_read_request_line_bytes) {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        }
        const read_request_line = read_request_line_fba.allocator().dupe(u8, read_request_line_unowned) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        const request_line = rl.parse(read_request_line) catch |err| switch (err) {
            error.InvalidRequestLine, error.InvalidPath => {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            },
            error.UnsupportedMethod => {
                try w.writeAll("HTTP/1.1 405\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            },
            error.UnsupportedVersion => {
                try w.writeAll("HTTP/1.1 505\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            },
        };
        const route = router.find(request_line.path) orelse {
            try w.writeAll("HTTP/1.1 404\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        var request_headers_map = h.Headers.init(request_headers_map_fba.allocator());
        read_request_headers: while (true) {
            const read_request_header_slice = read_http_line(r) catch {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            };
            const read_request_header_unowned = read_request_header_slice orelse {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            };
            if (read_request_header_unowned.len > config.max_read_request_headers_bytes) {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            }
            const read_request_header = read_request_headers_fba.allocator().dupe(u8, read_request_header_unowned) catch {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            };
            if (std.mem.eql(u8, read_request_header, "")) break :read_request_headers;
            request_headers_map.parse(read_request_header) catch {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            };
        }
        const content_length_string = request_headers_map.get("Content-Length") orelse {
            try w.writeAll("HTTP/1.1 411\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        const content_length_number = std.fmt.parseUnsigned(usize, content_length_string, 10) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        if (content_length_number > config.max_read_request_body_bytes) {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        }
        const content_type = request_headers_map.get("Content-Type") orelse {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        if (!std.mem.eql(u8, content_type, "application/json")) {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        }
        const request_body_raw = read_request_body_fba.allocator().alloc(u8, content_length_number) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        read_body_exact(r, request_body_raw) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        const request_body_valid = std.json.validate(json_validate_fba.allocator(), request_body_raw) catch {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        if (!request_body_valid) {
            try w.writeAll("HTTP/1.1 400\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        }
        json_validate_fba.reset();
        const request = req.Request{ .request_line = request_line, .headers = request_headers_map, .body_raw = request_body_raw, .body_allocator = request_body_parse_fba.allocator() };
        const response_headers_map = h.Headers.init(response_headers_map_fba.allocator());
        var response = res.Response{
            .status_line = sl.StatusLine{ .version = v.Version.http11, .status = s.Status.ok },
            .headers = response_headers_map,
            .body_raw = "{}",
            .body_allocator = response_body_fba.allocator(),
            .body_stringify_allocator = response_body_stringify_fba.allocator(),
        };
        route.handler(request, &response) catch |err| switch (err) {
            error.CannotParseBody => {
                try w.writeAll("HTTP/1.1 400\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            },
            error.CannotStringifyBody, error.InvalidHeader, error.InvalidHeaderName, error.InvalidHeaderValue, error.OutOfSpace, error.InvalidStatusLine, error.InvalidStatusCode, error.UnsupportedVersion => {
                try w.writeAll("HTTP/1.1 500\r\n\r\n");
                try w.flush();
                connection.stream.close();
                continue :accept_loop;
            },
        };
        const response_body_valid = std.json.validate(json_validate_fba.allocator(), response.body_raw) catch {
            try w.writeAll("HTTP/1.1 500\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        };
        if (!response_body_valid) {
            try w.writeAll("HTTP/1.1 500\r\n\r\n");
            try w.flush();
            connection.stream.close();
            continue :accept_loop;
        }
        // status line
        try w.print("{s} {s}\r\n", .{ response.status_line.version.to_string(), response.status_line.status.to_string() });
        // headers
        try w.writeAll("Connection: close\r\n");
        try w.writeAll("Content-Type: application/json\r\n");
        try w.print("Content-Length: {d}\r\n", .{response.body_raw.len});
        var headers_iterator = response.headers.iterator();
        while (headers_iterator.next()) |header| {
            try w.print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
        }
        // body
        try w.print("\r\n{s}", .{response.body_raw});
        try w.flush();
        connection.stream.close();
    }
}

fn read_body_exact(reader: *std.Io.Reader, request_body_raw: []u8) !void {
    try reader.readSliceAll(request_body_raw);
}

fn read_http_line(reader: *std.Io.Reader) !?[]const u8 {
    const line = try reader.takeDelimiter('\r');
    if (line == null) return null;
    if (try reader.takeByte() != '\n') return error.InvalidLineEnding;
    return line;
}

test "read_body_exact reads full body" {
    var stream: std.Io.Reader = .fixed("abc");
    var read_buffer: [3]u8 = undefined;
    try read_body_exact(&stream, &read_buffer);
    try expect_equal_strings("abc", &read_buffer);
}

test "read_body_exact fails on truncated body" {
    var stream: std.Io.Reader = .fixed("ab");
    var read_buffer: [3]u8 = undefined;
    try expect_error(error.EndOfStream, read_body_exact(&stream, &read_buffer));
}
