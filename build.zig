const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zest_module = b.addModule("zest", .{
        .root_source_file = b.path("src/zest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zest",
        .linkage = .static,
        .root_module = zest_module,
    });
    b.installArtifact(lib);

    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/zest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .root_module = tests_module,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const example_name = b.option([]const u8, "example", "The example to build & run") orelse "scouter";
    const example_file = if (std.mem.eql(u8, example_name, "scouter"))
        "examples/scouter.zig"
    else
        "examples/scouter.zig";

    const example_module = b.createModule(.{
        .root_source_file = b.path(example_file),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zest", .module = zest_module }},
    });
    const example = b.addExecutable(.{
        .name = example_name,
        .root_module = example_module,
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    run_example.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_example.addArgs(args);
    }

    const example_step = b.step("example", "Run example");
    example_step.dependOn(&run_example.step);
}
