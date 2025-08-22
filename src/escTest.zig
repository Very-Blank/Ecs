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
}

test "Iterating over a component" {
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

    var iterator: Iterator(Position) = ecs.getIterator(Position, struct {}, struct { Tag }).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.buffers.len == 1);
    try std.testing.expect(iterator.buffers[0].len == 100);

    var iterator2: Iterator(Position) = ecs.getIterator(Position, struct {}, struct {}).?;
    defer iterator2.deinit();

    try std.testing.expect(iterator2.buffers.len == 2);
    try std.testing.expect(iterator2.buffers[0].len == 100);
    try std.testing.expect(iterator2.buffers[1].len == 100);
}
