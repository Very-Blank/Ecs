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

    for (0..100_000) |_| {
        _ = ecs.createEntity(struct { Position }, .{
            Position{ .x = 1, .y = 3 },
        });
    }

    for (0..100_000) |_| {
        _ = ecs.createEntity(struct {
            Velocity,
            Position,
            Collider,
        }, .{
            Velocity{ .x = 1, .y = 3 },
            Position{ .x = 1, .y = 3 },
            Collider{ .x = 1, .y = 3 },
        });
    }

    for (0..100_000) |_| {
        _ = ecs.createEntity(struct {
            Collider,
            Velocity,
            Position,
        }, .{
            Collider{ .x = 1, .y = 3 },
            Velocity{ .x = 1, .y = 3 },
            Position{ .x = 1, .y = 3 },
        });
    }

    std.debug.print("component count {any}\n", .{ecs.componentManager.components.items.len});
    std.debug.print("archetype count {any}\n", .{ecs.entityManager.archetypes.items.len});
    std.debug.print("archetype {any}\n", .{ecs.entityManager.archetypes.items[0]});
    std.debug.print("archetype {any}\n", .{ecs.entityManager.archetypes.items[1]});

    ecs.deinit();

    // var archetype = Archetype.init(allocator);
    // defer archetype.deinit();
    // try archetype.registerComponent(Position);
    //
    // const positions = try archetype.getComponentBuffer(Position);
    // try positions.append(Position, .{ .x = 10, .y = 20 });
    // try positions.append(Position, .{ .x = 38, .y = 3434 });
    // try positions.append(Position, .{ .x = 868, .y = 44 });
    //
    // const position: *Position = positions.get(Position, 0);
    // position.*.x = 500;
    // position.*.y = 40000;
    // positions.remove(0);
    //
    // std.debug.print("{any}\n", .{positions.get(Position, 0)});
    // std.debug.print("{any}\n", .{positions.get(Position, 1)});
}
