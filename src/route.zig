const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const b = @import("body.zig");
const h = @import("headers.zig");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const p = @import("path.zig");
const sl = @import("status_line.zig");

pub const HandlerError = b.ParseBodyError || b.StringifyBodyError || h.HeadersError || sl.Error;
pub const Handler = *const fn (Request, *Response) HandlerError!void;

pub const Route = struct {
    path: []const u8,
    handler: Handler,

    pub fn init(comptime path: []const u8, handler: Handler) p.PathError!Route {
        const parsed_path = p.parse(path) catch @compileError("path \"" ++ path ++ "\" is invalid");
        assert(parsed_path.len > 0);
        assert(parsed_path[0] == '/');

        return Route{
            .path = parsed_path,
            .handler = handler,
        };
    }
};

fn scouter(_: Request, _: *Response) HandlerError!void {}

test "init stores path and handler pointer" {
    const route = comptime try Route.init("/scouter", scouter);
    try expectEqualStrings("/scouter", route.path);

    const expected_handler: Handler = scouter;
    try expect(@intFromPtr(expected_handler) == @intFromPtr(route.handler));
}
