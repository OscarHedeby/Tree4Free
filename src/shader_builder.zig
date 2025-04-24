const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const shaderc = zbgfx.shaderc;

pub fn build(
    allocator: std.mem.Allocator,
    shaderc_path: []const u8,
) !bgfx.ProgramHandle {
    // Load varying from file
    const varying_data = try readFileFromShaderDirs(
        allocator,
        "varying.def.sc",
    );
    defer allocator.free(varying_data);

    // Load fs_cube shader
    const fs_cube_data = try readFileFromShaderDirs(
        allocator,
        "fs_cubes.sc",
    );
    defer allocator.free(fs_cube_data);

    // Load vs_cube shader
    const vs_cube_data = try readFileFromShaderDirs(
        allocator,
        "vs_cubes.sc",
    );
    defer allocator.free(vs_cube_data);

    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);

    const path = try std.fs.path.join(
        allocator,
        &.{ exe_dir, "..", "include", "shaders" },
    );
    defer allocator.free(path);

    // Compile fs shader
    var fs_shader_options = shaderc.createDefaultOptionsForRenderer(
        bgfx.getRendererType(),
    );
    fs_shader_options.shaderType = .fragment;
    fs_shader_options.includeDirs = &.{path};

    const fs_shader = try shaderc.compileShader(
        allocator,
        shaderc_path,
        varying_data,
        fs_cube_data,
        fs_shader_options,
    );
    defer allocator.free(fs_shader);

    // Compile vs shader
    var vs_shader_options = shaderc.createDefaultOptionsForRenderer(
        bgfx.getRendererType(),
    );
    vs_shader_options.shaderType = .vertex;
    vs_shader_options.includeDirs = &.{path};

    const vs_shader = try shaderc.compileShader(
        allocator,
        shaderc_path,
        varying_data,
        vs_cube_data,
        vs_shader_options,
    );
    defer allocator.free(vs_shader);

    //
    // Create bgfx shader and program
    //
    const fs_cubes = bgfx.createShader(
        bgfx.copy(fs_shader.ptr, @intCast(fs_shader.len)),
    );
    const vs_cubes = bgfx.createShader(
        bgfx.copy(vs_shader.ptr, @intCast(vs_shader.len)),
    );
    const programHandle = bgfx.createProgram(
        vs_cubes,
        fs_cubes,
        true,
    );

    return programHandle;
}

fn readFileFromShaderDirs(
    allocator: std.mem.Allocator,
    filename: []const u8,
) ![:0]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);

    const path = try std.fs.path.join(
        allocator,
        &.{ exe_dir, "shaders", filename },
    );
    defer allocator.free(path);

    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const max_size = (try f.getEndPos()) + 1;
    var data = std.ArrayList(u8).init(allocator);
    try f.reader().readAllArrayList(
        &data,
        max_size,
    );

    return try data.toOwnedSliceSentinel(0);
}
