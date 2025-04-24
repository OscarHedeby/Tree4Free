const std = @import("std");
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

pub fn generateTree(alloc: std.mem.Allocator) !Tree {
    const n_points = 8;
    const num_verts = n_points * 2;
    const num_indices = n_points * 6;

    var w_verts = try alloc.alloc(PosColorVertex, num_verts);
    var w_indicies = try alloc.alloc(u16, num_indices);

    const ring = try alloc.alloc(PosColorVertex, n_points);
    defer alloc.free(ring);
    const ring_radius = 1.0;

    try genCircle(ring, ring_radius, Vec3f{ 0, 0, 0 });
    // Copy the ring vertices to the tree vertices
    for (0..n_points) |i| {
        w_verts[i] = ring[i];
    }
    try genCircle(ring, ring_radius, Vec3f{ 0, 0, 4 });
    // Copy the ring vertices to the tree vertices
    for (n_points..n_points * 2) |i| {
        w_verts[i] = ring[i - n_points];
    }

    // Generate the indices for the tree trunk
    for (0..n_points) |i| {
        const next = if (i + 1 == n_points) 0 else i + 1;
        w_indicies[i * 6 + 0] = @intCast(i);
        w_indicies[i * 6 + 1] = @intCast(next);
        w_indicies[i * 6 + 2] = @intCast(i + n_points);

        w_indicies[i * 6 + 3] = @intCast(i + n_points);
        w_indicies[i * 6 + 4] = @intCast(next);
        w_indicies[i * 6 + 5] = @intCast(next + n_points);
    }

    // Copy the vertices and indices to the tree
    const tree = Tree{
        .alloc = alloc,
        .verts = w_verts,
        .indices = w_indicies,
    };

    return tree;
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
            y + vector_offset[1],
            vector_offset[2],
            center.abgr,
        );
    }
}
