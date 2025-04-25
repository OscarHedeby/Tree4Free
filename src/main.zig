const std = @import("std");
const builtin = @import("builtin");
const math = std.math;

const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zm = @import("zmath");
const zbgfx = @import("zbgfx");
const shaderc = zbgfx.shaderc;
const bgfx = zbgfx.bgfx;

const backend_glfw_bgfx = @import("backend_glfw_bgfx.zig");
const shaders = @import("shader_builder.zig");

const TreeGen = @import("tree.zig");

const MAIN_FONT = @embedFile("Roboto-Medium.ttf");

const WIDTH = 1280;
const HEIGHT = 720;

var bgfx_clbs = zbgfx.callbacks.CCallbackInterfaceT{
    .vtable = &zbgfx.callbacks.DefaultZigCallbackVTable.toVtbl(),
};
var bgfx_alloc: zbgfx.callbacks.ZigAllocator = undefined;

var debug = true;
var vsync = true;

var last_v = zglfw.Action.release;
var last_d = zglfw.Action.release;
var last_r = zglfw.Action.release;
var old_flags = bgfx.ResetFlags_None;
var old_size = [2]i32{ WIDTH, HEIGHT };

// Initial Camera state
const initial_eye_x: f32 = 10.0;
const initial_eye_y: f32 = 0.0;
const initial_eye_z: f32 = 0.0;
const initial_target_x: f32 = 0.0;
const initial_target_y: f32 = 0.0;
const initial_target_z: f32 = 0.0;

// Camera view direction (fixed)
const dir_x = initial_target_x - initial_eye_x;
const dir_y = initial_target_y - initial_eye_y;
const dir_z = initial_target_z - initial_eye_z;

// Current Camera position variables (controlled by sliders)
var eye_x: f32 = initial_eye_x;
var eye_y: f32 = initial_eye_y;
var eye_z: f32 = initial_eye_z;

pub fn main() anyerror!u8 {
    // Init zglfw
    try zglfw.init();
    defer zglfw.terminate();

    // Create window
    zglfw.windowHint(.client_api, .no_api);
    const window = try zglfw.Window.create(
        WIDTH,
        HEIGHT,
        "ZBgfx - zgui",
        null,
    );
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    // Init bgfx init params
    var bgfx_init: bgfx.Init = undefined;
    bgfx.initCtor(&bgfx_init);

    const framebufferSize = window.getFramebufferSize();
    bgfx_init.resolution.width = @intCast(framebufferSize[0]);
    bgfx_init.resolution.height = @intCast(framebufferSize[1]);
    bgfx_init.platformData.ndt = null;
    bgfx_init.debug = true;

    bgfx_init.callback = &bgfx_clbs;

    // Set native handles
    switch (builtin.target.os.tag) {
        .linux => {
            bgfx_init.platformData.type = bgfx.NativeWindowHandleType.Default;
            bgfx_init.platformData.nwh = @ptrFromInt(
                zglfw.getX11Window(window),
            );
            bgfx_init.platformData.ndt = zglfw.getX11Display();
        },
        .windows => {
            bgfx_init.platformData.nwh = zglfw.getWin32Window(window);
        },
        else => |v| if (v.isDarwin()) {
            bgfx_init.platformData.nwh = zglfw.getCocoaWindow(window);
        } else undefined,
    }

    // Init bgfx

    // Do not create render thread
    _ = bgfx.renderFrame(-1);

    if (!bgfx.init(&bgfx_init)) std.process.exit(1);
    defer bgfx.shutdown();

    var tree_height: f32 = 20.0;
    var tree_thickness: f32 = 2.0;
    var tree_taper: f32 = 1.0;
    var tree_segment_height: f32 = 0.5;

    var gpa_tree = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa_tree.allocator();
    defer _ = gpa_tree.deinit();

    var tree_profile = TreeGen.TreeProfile{
        .height = tree_height,
        .thickness = tree_thickness,
        .taper = tree_taper,
        .segment_height = tree_segment_height,
    };

    var tree = try TreeGen.generateTree(tree_profile, allocator);
    defer tree.deinit();

    //
    // Create vertex buffer
    //
    const vertex_layout = TreeGen.PosColorVertex.layoutInit();
    var vbh = bgfx.createVertexBuffer(
        bgfx.makeRef(
            tree.verts.ptr,
            @intCast(tree.verts.len * @sizeOf(TreeGen.PosColorVertex)),
        ),
        &vertex_layout,
        bgfx.BufferFlags_None,
    );
    defer bgfx.destroyVertexBuffer(vbh);

    //
    // Create index buffer
    //
    var ibh = bgfx.createIndexBuffer(
        bgfx.makeRef(
            tree.indices.ptr,
            @intCast(tree.indices.len * @sizeOf(u16)),
        ),
        bgfx.BufferFlags_None,
    );
    defer bgfx.destroyIndexBuffer(ibh);

    var reset_flags = bgfx.ResetFlags_None;
    if (vsync) {
        reset_flags |= bgfx.ResetFlags_Vsync;
    }

    // Reset and clear
    bgfx.reset(
        @intCast(framebufferSize[0]),
        @intCast(framebufferSize[1]),
        reset_flags,
        bgfx_init.resolution.format,
    );

    // Set view 0 clear state.
    bgfx.setViewClear(
        0,
        bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
        0x303030ff,
        1.0,
        0,
    );

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const shaderc_path = try shaderc.shadercFromExePath(gpa_allocator);
    defer gpa_allocator.free(shaderc_path);

    var programHandle = shaders.build(
        gpa_allocator,
        shaderc_path,
    ) catch |err| {
        std.log.err("Build program failed => {}", .{err});
        return 1;
    };
    defer bgfx.destroyProgram(programHandle);

    zgui.init(gpa_allocator);
    defer zgui.deinit();

    // Load main font
    var main_cfg = zgui.FontConfig.init();
    main_cfg.font_data_owned_by_atlas = false;
    _ = zgui.io.addFontFromMemoryWithConfig(
        MAIN_FONT,
        std.math.floor(16 * scale_factor),
        main_cfg,
        null,
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    backend_glfw_bgfx.init(window);
    defer backend_glfw_bgfx.deinit();

    //
    // Main loop
    //
    //
    // Reset and clear
    //
    bgfx.reset(
        @intCast(framebufferSize[0]),
        @intCast(framebufferSize[1]),
        reset_flags,
        bgfx_init.resolution.format,
    );

    // Set view 0 clear state.
    bgfx.setViewClear(
        0,
        bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
        0x303030ff,
        1.0,
        0,
    );

    //
    // Create view and proj matrices
    //
    var viewMtx: zm.Mat = undefined; // Will be updated in the loop
    var projMtx: zm.Mat = undefined;

    // Initialize projection matrix before first frame
    {
        const size0 = window.getFramebufferSize();
        const aspect0 = @as(f32, @floatFromInt(size0[0])) / @as(
            f32,
            @floatFromInt(size0[1]),
        );
        projMtx = zm.perspectiveFovRhGl(0.25 * math.pi, aspect0, 0.1, 100.0);
        old_size = size0;
        old_flags = reset_flags;
    }

    //
    // Default state
    //
    const state = 0 | bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA |
        bgfx.StateFlags_WriteZ | bgfx.StateFlags_DepthTestLess |
        bgfx.StateFlags_Msaa | bgfx.StateFlags_CullCw;

    //
    // Main loop
    //
    const start_time: i64 = std.time.milliTimestamp();
    _ = start_time;
    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        //
        // Poll events
        //
        zglfw.pollEvents();

        //
        // Check keyboard
        //
        if (last_d != .press and window.getKey(.d) == .press) {
            debug = !debug;
        }
        if (last_v != .press and window.getKey(.v) == .press) {
            vsync = !vsync;
        }
        last_v = window.getKey(.v);
        last_d = window.getKey(.d);

        if (last_r != .press and window.getKey(.r) == .press) {
            if (shaders.build(
                gpa_allocator,
                shaderc_path,
            )) |program| {
                bgfx.destroyProgram(programHandle);
                programHandle = program;
            } else |err| {
                std.log.err("Build program failed => {}", .{err});
            }
        }
        last_r = window.getKey(.r);

        //
        // New flags?
        //
        reset_flags = bgfx.ResetFlags_None;
        if (vsync) {
            reset_flags |= bgfx.ResetFlags_Vsync;
        }

        //
        // Show debug
        //
        if (debug) {
            bgfx.setDebug(bgfx.DebugFlags_Stats);
        } else {
            bgfx.setDebug(bgfx.DebugFlags_None);
        }

        //
        // If resolution or flags is changed reset.
        //
        const size = window.getFramebufferSize();
        if (old_flags != reset_flags or
            old_size[0] != size[0] or
            old_size[1] != size[1])
        {
            const aspect_ratio = @as(f32, @floatFromInt(size[0])) / @as(
                f32,
                @floatFromInt(size[1]),
            );
            projMtx = zm.perspectiveFovRhGl(
                0.25 * math.pi,
                aspect_ratio,
                0.1,
                100.0,
            );

            bgfx.reset(
                @intCast(size[0]),
                @intCast(size[1]),
                reset_flags,
                bgfx_init.resolution.format,
            );
            old_size = size;
            old_flags = reset_flags;
        }

        //
        //  Preapare view
        //
        // Calculate current target based on eye and fixed direction
        const target_x = eye_x + dir_x;
        const target_y = eye_y + dir_y;
        const target_z = eye_z + dir_z;
        // Update view matrix based on eye variables
        viewMtx = zm.lookAtRh(
            // Use variables here
            zm.f32x4(eye_x, eye_y, eye_z, 1.0),
            // Use calculated target
            zm.f32x4(target_x, target_y, target_z, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        bgfx.setViewTransform(
            0,
            &zm.matToArr(viewMtx),
            &zm.matToArr(projMtx),
        );
        bgfx.setViewRect(
            0,
            0,
            0,
            @intCast(size[0]),
            @intCast(size[1]),
        );
        bgfx.touch(0);
        bgfx.dbgTextClear(0, false);

        const trans = zm.translation(0.0, 0.0, 0.0);
        const rotX = zm.rotationX(0);
        const rotY = zm.rotationY(0);
        const rotXY = zm.mul(rotX, rotY);
        const modelMtx = zm.mul(rotXY, trans);

        _ = bgfx.setTransform(&zm.matToArr(modelMtx), 1);

        bgfx.setVertexBuffer(0, vbh, 0, @intCast(tree.verts.len));
        bgfx.setIndexBuffer(ibh, 0, @intCast(tree.indices.len));
        bgfx.setState(state, 0);
        bgfx.submit(
            0,
            programHandle,
            0,
            bgfx.DiscardFlags_None,
        );

        // Do some zgui stuff
        backend_glfw_bgfx.newFrame(
            @intCast(size[0]),
            @intCast(size[1]),
        );
        // zgui.showDemoWindow(null); // Optionally keep or remove demo window

        // Add Camera Control Window
        if (zgui.begin("Camera Controls", .{})) {
            _ = zgui.sliderFloat(
                "Eye X",
                .{ .v = &eye_x, .min = -20.0, .max = 40.0 },
            );
            _ = zgui.sliderFloat(
                "Eye Y",
                .{ .v = &eye_y, .min = -20.0, .max = 40.0 },
            );
            _ = zgui.sliderFloat(
                "Eye Z",
                .{ .v = &eye_z, .min = -20.0, .max = 40.0 },
            );
        }
        zgui.end();

        // Tree Profile Controls
        var tree_changed = false;
        if (zgui.begin("Tree Profile", .{})) {
            tree_changed = tree_changed or
                zgui.sliderFloat("Height", .{
                    .v = &tree_height,
                    .min = 1.0,
                    .max = 50.0,
                });
            tree_changed = tree_changed or
                zgui.sliderFloat("Thickness", .{
                    .v = &tree_thickness,
                    .min = 0.1,
                    .max = 10.0,
                });
            tree_changed = tree_changed or
                zgui.sliderFloat("Taper", .{
                    .v = &tree_taper,
                    .min = 0.5,
                    .max = 3.0,
                });
            tree_changed = tree_changed or
                zgui.sliderFloat("Segment Height", .{
                    .v = &tree_segment_height,
                    .min = 0.05,
                    .max = 2.0,
                });
        }
        zgui.end();

        // Regenerate tree mesh if any parameter changed
        if (tree_changed) {
            tree.deinit();
            tree_profile = TreeGen.TreeProfile{
                .height = tree_height,
                .thickness = tree_thickness,
                .taper = tree_taper,
                .segment_height = tree_segment_height,
            };
            tree = try TreeGen.generateTree(tree_profile, allocator);

            // Re-upload vertex/index buffers
            bgfx.destroyVertexBuffer(vbh);
            bgfx.destroyIndexBuffer(ibh);

            vbh = bgfx.createVertexBuffer(
                bgfx.makeRef(
                    tree.verts.ptr,
                    @intCast(tree.verts.len * @sizeOf(TreeGen.PosColorVertex)),
                ),
                &vertex_layout,
                bgfx.BufferFlags_None,
            );
            ibh = bgfx.createIndexBuffer(
                bgfx.makeRef(
                    tree.indices.ptr,
                    @intCast(tree.indices.len * @sizeOf(u16)),
                ),
                bgfx.BufferFlags_None,
            );
        }

        backend_glfw_bgfx.draw();

        // Render Frame
        _ = bgfx.frame(false);
    }

    return 0;
}
