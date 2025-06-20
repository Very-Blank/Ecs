const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const qoi = b.addModule("ecs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Ecs",
        .root_module = qoi,
    });

    b.installArtifact(lib);

    // Tests:
    const testFiles = .{"escTest"};

    const test_step = b.step("test", "Run unit tests");

    inline for (testFiles) |fileName| {
        const testModule = b.createModule(.{
            .root_source_file = b.path("src/" ++ fileName ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        const unitTest = b.addTest(.{
            .root_module = testModule,
        });

        const runUnitTest = b.addRunArtifact(unitTest);

        test_step.dependOn(&runUnitTest.step);
    }
}
