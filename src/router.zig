const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expect_equal_strings = std.testing.expectEqualStrings;
const Route = @import("route.zig").Route;
const HandlerError = @import("route.zig").HandlerError;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

pub const Router = struct {
    routes: []const Route,

    pub fn init(comptime routes: []const Route) Router {
        for (routes, 0..) |route_1, i_1| {
            assert(route_1.path.len > 0);
            assert(route_1.path[0] == '/');

            for (routes, 0..) |route_2, i_2| {
                if (i_1 != i_2 and std.mem.eql(u8, route_1.path, route_2.path)) {
                    @compileError("duplicate path \"" ++ route_1.path ++ "\" found in routes");
                }
            }
        }

        return Router{ .routes = routes };
    }

    pub fn find(self: Router, path: []const u8) ?Route {
        for (self.routes) |route| {
            if (std.mem.eql(u8, path, route.path)) return route;
        } else return null;
    }
};

fn scouter(_: Request, _: *Response) HandlerError!void {}
fn ping(_: Request, _: *Response) HandlerError!void {}

test "find returns route for exact path" {
    const routes = comptime .{
        try Route.init("/scouter", scouter),
        try Route.init("/ping", ping),
    };
    const router = comptime Router.init(&routes);

    const found = router.find("/ping") orelse unreachable;
    try expect_equal_strings("/ping", found.path);
}

test "find returns null for unknown path" {
    const routes = comptime .{
        try Route.init("/scouter", scouter),
    };
    const router = comptime Router.init(&routes);

    try expect(router.find("/missing") == null);
}
