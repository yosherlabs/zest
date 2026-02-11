const std = @import("std");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

pub const ParseBodyError = error{
    CannotParseBody,
};

pub const StringifyBodyError = error{
    CannotStringifyBody,
};

pub const BodyError = ParseBodyError || StringifyBodyError;

pub fn parse(allocator: std.mem.Allocator, comptime T: type, body: []const u8) ParseBodyError!T {
    return std.json.parseFromSliceLeaky(T, allocator, body, .{}) catch ParseBodyError.CannotParseBody;
}

pub fn stringify(
    allocator: std.mem.Allocator,
    comptime T: type,
    content: T,
) StringifyBodyError![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    std.json.Stringify.value(content, .{}, &out.writer) catch {
        return StringifyBodyError.CannotStringifyBody;
    };
    return out.toOwnedSlice() catch StringifyBodyError.CannotStringifyBody;
}

test "testing 1" {
    const Config = struct {
        greeting: []const u8,
        hello: []const u8,
        you: u8,
    };
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const body = "{\"greeting\": \"9999\", \"hello\": \"88\", \"you\": 9}";
    const result = try parse(fba.allocator(), Config, body);
    try expectEqualStrings(result.greeting, "9999");
    try expectEqualStrings(result.hello, "88");
    try expect(result.you == 9);
}

test "testing 2" {
    const Config = struct {};
    const config = Config{};
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const result = try stringify(fba.allocator(), Config, config);
    try expectEqualStrings("{}", result);
}
