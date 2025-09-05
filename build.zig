const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ecs = b.addModule("ecs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Ecs",
        .root_module = ecs,
    });

    b.installArtifact(lib);

    const ecsTests = b.createModule(.{
        .root_source_file = b.path("src/ecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");

    const unitTest = b.addTest(.{
        .root_module = ecsTests,
    });

    const runUnitTest = b.addRunArtifact(unitTest);

    test_step.dependOn(&runUnitTest.step);
}
