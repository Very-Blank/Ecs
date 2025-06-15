const std = @import("std");
const builtin = @import("builtin");

const Ecs = @import("ecs.zig").Ecs;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const Position = struct {
    x: u32,
    y: u32,
};

pub const Velocity = struct {
    x: u32,
    y: u32,
};

pub const Collider = struct {
    x: u32,
    y: u32,
};

pub fn main() !void {
    const allocator: std.mem.Allocator, const is_debug: bool = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        std.debug.print("Debug allocator: {any}\n", .{debug_allocator.deinit()});
    };

    var ecs: Ecs = .init(allocator);
    defer ecs.deinit();

    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 3 },
    });

    ecs.destroyEntity(entity);

    std.debug.print("component count {any}\n", .{ecs.componentManager.components.items.len});
    std.debug.print("archetype count {any}\n", .{ecs.entityManager.archetypes.items.len});
    std.debug.print("archetype {any}\n", .{ecs.entityManager.archetypes.items[0]});
}
