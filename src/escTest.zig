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

pub const Tag = struct {};
pub const Tag2 = struct {};

test "Creating a new entity" {
    var ecs: Ecs(struct {
        struct { Position, Tag },
        struct { Position },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            struct { Position, Tag },
            .{ Position{ .x = 5, .y = 5 }, .{} },
        );
        _ = ecs.createEntity(
            struct { Position },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    const archetype = ecs.getArchetype(struct { Position, Tag });
    for (archetype.container[0].items) |position| {
        std.debug.print("position value: {}\n", .{position});
    }
}
