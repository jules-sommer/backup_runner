const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const folders = b.addStaticLibrary(.{
        .name = "folders",
        .root_source_file = b.path("src/folders/folders.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(folders);

    const exe = b.addExecutable(.{
        .name = "backup-runner",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("folders", &folders.root_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
