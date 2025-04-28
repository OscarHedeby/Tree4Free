const std = @import("std");
const zm = @import("zmath");
const Vec3f = @Vector(3, f32);
const meta = std.meta;

pub const Branch = struct {
    allocator: std.mem.Allocator,
    start: Vec3f,
    end: Vec3f,
    segment_nr: i16,

    children: ?[]Branch,
    profile: TreeProfile,

    pub fn init(
        start: Vec3f,
        end: Vec3f,
        segment_nr: i16,
        allocator: std.mem.Allocator,
        profile: TreeProfile,
    ) Branch {
        return .{
            .start = start,
            .end = end,
            .children = null,
            .segment_nr = segment_nr,
            .allocator = allocator,
            .profile = profile,
        };
    }

    pub fn grow(self: *Branch) !void {
        // TODO: Growth should not be linear
        const dx = self.end[0] - self.start[0];
        const dy = self.end[1] - self.start[1];
        const dz = self.end[2] - self.start[2];
        const len = std.math.sqrt(dx * dx + dy * dy + dz * dz);
        const dir = Vec3f{ dx / len, dy / len, dz / len };
        var rn = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = self.profile.seed;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });

        self.end = Vec3f{
            self.end[0] + dir[0],
            self.end[1] + dir[1],
            self.end[2] + dir[2],
        };

        if (self.children != null) {
            for (0..self.children.?.len) |i| {
                try self.children.?[i].grow();
            }
        }

        // Add branch
        if (len > 3.0) {
            const rand = rn.random();
            // Generate a random unit vector within a cone pointing upwards (y axis)
            // Cone angle (in radians), e.g., 30 degrees
            const cone_angle = std.math.degreesToRadians(30.0);
            const cos_cone = std.math.cos(cone_angle);

            // Sample uniformly within the cone
            const u = rand.float(f32);
            const v = rand.float(f32);
            const cos_theta = (1.0 - u) + u * cos_cone; // interpolate between 1 and cos(cone)
            const sin_theta = std.math.sqrt(1.0 - cos_theta * cos_theta);
            const phi = 2.0 * std.math.pi * v;

            // Local direction in cone (aligned with y axis)
            const offshoot_dir = Vec3f{
                sin_theta * std.math.cos(phi),
                cos_theta,
                sin_theta * std.math.sin(phi),
            };
            const offshoot = Branch.init(
                self.end,
                Vec3f{
                    self.end[0] + offshoot_dir[0],
                    self.end[1] + offshoot_dir[1],
                    self.end[2] + offshoot_dir[2],
                },
                self.segment_nr + 1,
                self.allocator,
                self.profile,
            );
            var childs: i32 = 1;
            if (self.children != null) {
                childs += @intCast(self.children.?.len);
            }
            const newChildren = try self.allocator.alloc(Branch, @intCast(childs));
            if (self.children != null) {
                for (0..self.children.?.len) |i| {
                    newChildren[i] = self.children.?[i];
                }
            }
            newChildren[@intCast(childs - 1)] = offshoot;
            self.children = newChildren;
        }
    }
};

const TreeProfile = struct {
    age: usize,
    seed: u64,
};

pub fn GrowTree(allocator: std.mem.Allocator, profile: TreeProfile) !Branch {
    var branch = Branch.init(
        Vec3f{ 0, 0, 0 },
        Vec3f{ 0, 1, 0 }, // initial end vector instead of a scalar distance
        0,
        allocator,
        profile,
    );
    for (0..profile.age) |_| {
        try branch.grow();
    }
    return branch;
}
