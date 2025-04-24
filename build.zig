const std = @import("std");

const zbgfx = @import("zbgfx");

pub fn build(
    b: *std.Build,
) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath = b.dependency(
        "zmath",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // zglfw
    const zglfw = b.dependency(
        "zglfw",
        .{
            .target = target,
            .optimize = optimize,
        },
    );
    // ZGUI
    const zgui = b.dependency(
        "zgui",
        .{
            .target = target,
            .optimize = optimize,
            .backend = .glfw,
        },
    );

    // ZBgfx
    const zbgfx_dep = b.dependency(
        "zbgfx",
        .{
            .target = target,
            .optimize = optimize,
            .imgui_include = zgui.path("libs").getPath(b),
        },
    );

    const exe = b.addExecutable(.{
        .name = "trees",
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
    });
    b.installArtifact(exe);
    exe.linkLibrary(zbgfx_dep.artifact("bgfx"));

    b.installArtifact(zbgfx_dep.artifact("shaderc"));

    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.root_module.addImport("zmath", zmath.module("root"));
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.root_module.addImport("zbgfx", zbgfx_dep.module("zbgfx"));

    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.linkLibrary(zgui.artifact("imgui"));

    // Install core shaders
    const install_shaders_includes = b.addInstallDirectory(.{
        .install_dir = .header,
        .install_subdir = "shaders",
        .source_dir = zbgfx_dep.path("shaders"),
    });
    exe.step.dependOn(&install_shaders_includes.step);

    // Install project shaders
    const install_example_shaders = b.addInstallDirectory(.{
        .install_dir = .bin,
        .install_subdir = "shaders",
        .source_dir = b.path("./src"),
        .include_extensions = &.{".sc"},
    });
    exe.step.dependOn(&install_example_shaders.step);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
