const std = @import("std");
const builtin = @import("builtin");
const meta = std.meta;

const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const Vec3f = @Vector(3, f32);

//
// Vertex layout definiton
//
pub const PosColorVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    nx: f32,
    ny: f32,
    nz: f32,

    pub fn init(
        x: f32,
        y: f32,
        z: f32,
        nx: f32,
        ny: f32,
        nz: f32,
    ) PosColorVertex {
        return .{
            .x = x,
            .y = y,
            .z = z,
            .nx = nx,
            .ny = ny,
            .nz = nz,
        };
    }

    pub fn layoutInit() bgfx.VertexLayout {
        // static local
        const L = struct {
            var posColorLayout = std.mem.zeroes(bgfx.VertexLayout);
        };

        L.posColorLayout.begin(bgfx.RendererType.Noop)
            .add(bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false)
            .add(bgfx.Attrib.Normal, 3, bgfx.AttribType.Float, true, false)
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

pub const TreeProfile = struct {
    height: f32,
    thickness: f32,
    taper: f32, // 1.0 = no taper, >1.0 more bulge at base, <1.0 sharper taper
    segment_height: f32,

    /// Returns the number of segments for the given height and segment_height
    fn computeSegments(self: TreeProfile) usize {
        return @max(
            2,
            @as(u32, @intFromFloat(@ceil(self.height / self.segment_height))),
        );
    }

    /// Returns the TreeSettings for this profile
    pub fn toSettings(self: TreeProfile) TreeSettings {
        const segments = self.computeSegments();
        return TreeSettings{
            .segments = segments,
            .radius = self.thickness,
            .heightStep = self.height / @as(f32, @floatFromInt(segments - 1)),
            .taper = self.taper,
        };
    }
};

const TreeSettings = struct {
    segments: usize,
    radius: f32,
    heightStep: f32,
    taper: f32,

    pub fn strEncode(self: TreeSettings) [8]u8 {
        return packU16To2Bytes(@intCast(self.segments)) ++
            packF16To2Bytes(@floatCast(self.radius)) ++
            packF16To2Bytes(@floatCast(self.heightStep)) ++
            packF16To2Bytes(@floatCast(self.taper));
    }
};

pub fn generateTree(profile: TreeProfile, alloc: std.mem.Allocator) !Tree {
    const settings = profile.toSettings();
    const n_points = 8;
    // +1 for the cap ring, +1 for the tip vertex
    const num_verts = n_points * (settings.segments + 1) + 1;
    // indices for the sides + indices for the tip (n_points triangles)
    const num_indices = (settings.segments) * n_points * 6 + n_points * 3;

    var w_verts = try alloc.alloc(PosColorVertex, num_verts);
    var w_indices = try alloc.alloc(u16, num_indices);

    const ring = try alloc.alloc(PosColorVertex, n_points);
    defer alloc.free(ring);

    // Generate each ring along the height, with tapering radius
    const base_scale: f32 = settings.taper; // base is taper x the given radius
    const min_radius: f32 = settings.radius * 0.2;
    for (0..settings.segments) |seg| {
        const t = @as(f32, @floatFromInt(seg)) / @as(
            f32,
            @floatFromInt(settings.segments - 1),
        );
        // Tree trunk profile: thick at base, then slims down
        // Cubic ease-out: (1-t)^2 * (1 - 0.5*t) gives a bulge at the base
        const profile_shape = (1.0 - t) * (1.0 - t) * (1.0 - 0.5 * t);
        const seg_radius = min_radius +
            (base_scale * settings.radius - min_radius) * profile_shape;
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

    // Add cap ring at the top (not part of segments)
    const cap_ring_y = @as(f32, @floatFromInt(settings.segments)) *
        settings.heightStep;
    try genCircle(ring, min_radius, Vec3f{
        0,
        cap_ring_y,
        0,
    });
    for (0..n_points) |i| {
        w_verts[settings.segments * n_points + i] = ring[i];
    }

    // Add tip vertex above the cap ring
    const tip_y = cap_ring_y + settings.heightStep * 0.5;
    const tip_vertex = PosColorVertex.init(
        0,
        tip_y,
        0,
        0,
        1,
        0,
    );
    w_verts[n_points * (settings.segments + 1)] = tip_vertex;

    // Generate indices to connect rings (sides)
    var idx_pos: usize = 0;
    for (0..settings.segments) |seg| {
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

    // Cap: connect each last ring vertex to the tip vertex
    const last_ring_base = settings.segments * n_points;
    const tip_idx = n_points * (settings.segments + 1);
    for (0..n_points) |i| {
        const next = if (i + 1 == n_points) 0 else i + 1;
        // Reverse winding order:
        w_indices[idx_pos] = @intCast(last_ring_base + next);
        idx_pos += 1;
        w_indices[idx_pos] = @intCast(last_ring_base + i);
        idx_pos += 1;
        w_indices[idx_pos] = @intCast(tip_idx);
        idx_pos += 1;
    }

    return Tree{
        .alloc = alloc,
        .verts = w_verts,
        .indices = w_indices,
    };
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

    var x: f32 = 0;
    var y: f32 = 0;
    var nx: f32 = 0;
    var ny: f32 = 0;
    var nz: f32 = 0;

    for (0..verts.len) |i| {
        const theta = @as(f32, @floatFromInt(i)) * angle;
        x = radius * std.math.cos(theta);
        y = radius * std.math.sin(theta);
        // Compute normals
        nx = std.math.cos(theta);
        ny = std.math.sin(theta);
        nz = 0.0;

        verts[i] = PosColorVertex.init(
            x + vector_offset[0],
            vector_offset[1],
            y + vector_offset[2],
            nx,
            ny,
            nz,
        );
    }
}
