const std = @import("std");
const Ecs = @import("ecs.zig").Ecs;
const Row = @import("archetype.zig").RowType;
const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("iterator.zig").TupleIterator;
const EntityType = @import("entity.zig").EntityType;

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

test "Creating a new entity" {
    var ecs: Ecs(struct { struct { Position } }) = .init(std.testing.allocator);
    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Position }, .{Position{ .x = 1, .y = 3 }});
    }
}
