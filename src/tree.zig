const std = @import("std");
const builtin = @import("builtin");
const meta = std.meta;

const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const Vec3f = @Vector(3, f32);

//
// Vertex layout definiton
//
const PosColorVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    abgr: u32,

    fn init(x: f32, y: f32, z: f32, abgr: u32) PosColorVertex {
        return .{
            .x = x,
            .y = y,
            .z = z,
            .abgr = abgr,
        };
    }

    fn layoutInit() bgfx.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(bgfx.VertexLayout);
        };

        L.posColorLayout.begin(bgfx.RendererType.Noop)
            .add(bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false)
            .add(bgfx.Attrib.Color0, 4, bgfx.AttribType.Uint8, true, false)
            .end();

        return L.posColorLayout;
    }
};

const Tree = struct {
    alloc: std.mem.Allocator,
    verts: []PosColorVertex,
    indices: []u16,

    pub fn deinit(self: Tree) void {
        self.alloc.free(self.verts);
        self.alloc.free(self.indices);
    }
};

fn packU16To2Bytes(value: u16) [2]u8 {
    const bits: u16 = @bitCast(value);
    return .{
        @intCast(bits >> 8), // high byte
        @intCast(bits & 0xFF), // low  byte
    };
}

fn packF16To2Bytes(value: f16) [2]u8 {
    const bits: u16 = @bitCast(value);
    return .{
        @intCast(bits >> 8), // high byte
        @intCast(bits & 0xFF), // low  byte
    };
}

pub const TreeSettings = struct {
    segments: usize,
    radius: f32,
    heightStep: f32,

    pub fn strEncode(self: TreeSettings) [6]u8 {
        return packU16To2Bytes(@intCast(self.segments)) ++
            packF16To2Bytes(@floatCast(self.radius)) ++
            packF16To2Bytes(@floatCast(self.heightStep));
    }
};

pub fn generateTree(settings: TreeSettings, alloc: std.mem.Allocator) !Tree {
    const n_points = 8;
    // +1 for the cap vertex at the top
    const num_verts = n_points * settings.segments + 1;
    // indices for the sides + indices for the cap (n_points triangles)
    const num_indices = (settings.segments - 1) * n_points * 6 + n_points * 3;

    var w_verts = try alloc.alloc(PosColorVertex, num_verts);
    var w_indices = try alloc.alloc(u16, num_indices);

    const ring = try alloc.alloc(PosColorVertex, n_points);
    defer alloc.free(ring);

    // Generate each ring along the height, with tapering radius
    for (0..settings.segments) |seg| {
        const t = @as(f32, @floatFromInt(seg)) / @as(
            f32,
            @floatFromInt(settings.segments - 1),
        );
        // Linear taper: radius decreases from base to top
        const seg_radius = settings.radius * (1.0 - t);
        const offset = Vec3f{
            0,
            @as(f32, @floatFromInt(seg)) * settings.heightStep,
            0,
        };
        try genCircle(ring, seg_radius, offset);
        for (0..n_points) |i| {
            w_verts[seg * n_points + i] = ring[i];
        }
    }

    // Add cap vertex at the top center
    const cap_y = @as(
        f32,
        @floatFromInt(settings.segments - 1),
    ) * settings.heightStep;
    const cap_vertex = PosColorVertex.init(
        0,
        cap_y,
        0,
        0xFFFFFFFF,
    );
    w_verts[n_points * settings.segments] = cap_vertex;

    // Generate indices to connect rings (sides)
    var idx_pos: usize = 0;
    for (0..settings.segments - 1) |seg| {
        const base0 = seg * n_points;
        const base1 = (seg + 1) * n_points;
        for (0..n_points) |i| {
            const next = if (i + 1 == n_points) 0 else i + 1;
            // First triangle (reverse order)
            w_indices[idx_pos] = @intCast(base0 + i);
            idx_pos += 1;
            w_indices[idx_pos] = @intCast(base1 + i);
            idx_pos += 1;
            w_indices[idx_pos] = @intCast(base0 + next);
            idx_pos += 1;

            // Second triangle (reverse order)
            w_indices[idx_pos] = @intCast(base1 + i);
            idx_pos += 1;
            w_indices[idx_pos] = @intCast(base1 + next);
            idx_pos += 1;
            w_indices[idx_pos] = @intCast(base0 + next);
            idx_pos += 1;
        }
    }

    // Cap: connect each last ring vertex to the cap vertex
    const last_ring_base = (settings.segments - 1) * n_points;
    const cap_idx = n_points * settings.segments;
    for (0..n_points) |i| {
        const next = if (i + 1 == n_points) 0 else i + 1;
        w_indices[idx_pos] = @intCast(last_ring_base + i);
        idx_pos += 1;
        w_indices[idx_pos] = @intCast(last_ring_base + next);
        idx_pos += 1;
        w_indices[idx_pos] = @intCast(cap_idx);
        idx_pos += 1;
    }

    return Tree{ .alloc = alloc, .verts = w_verts, .indices = w_indices };
}

const TreeGenError = error{
    InvalidNode,
    InvalidVertex,
    InvalidIndex,
};

pub fn genCircle(
    verts: []PosColorVertex,
    radius: f32,
    vector_offset: Vec3f,
) TreeGenError!void {
    const angle = 2.0 * std.math.pi / @as(f32, @floatFromInt(verts.len));
    const center = PosColorVertex.init(0, 0, 0, 0xFFFFFFFF);

    for (0..verts.len) |i| {
        const theta = @as(f32, @floatFromInt(i)) * angle;
        const x = radius * std.math.cos(theta);
        const y = radius * std.math.sin(theta);
        verts[i] = PosColorVertex.init(
            x + vector_offset[0],
            vector_offset[1],
            y + vector_offset[2],
            center.abgr,
        );
    }
}
