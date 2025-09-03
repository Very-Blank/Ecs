const std = @import("std");
const Ecs = @import("ecs.zig").Ecs;
const EmptyTags = @import("ecs.zig").EmptyTags;
const Template = @import("ecs.zig").Template;
const Row = @import("archetype.zig").RowType;
const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("tupleIterator.zig").TupleIterator;
const EntityType = @import("entity.zig").EntityType;

const ULandType = @import("uLandType.zig").ULandType;

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
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position}, .tags = null },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Collider, Position }, .tags = &[_]type{Tag} },
            .{ Collider{ .x = 5, .y = 5 }, Position{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = null },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    const archetype = ecs.getArchetype(.{ .components = &[_]type{ Collider, Position }, .tags = &[_]type{Tag} });
    _ = archetype;
}

test "Destroing an entity" {
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position}, .tags = null },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    const entityPtr = ecs.createEntity(
        .{ .components = &[_]type{Position}, .tags = null },
        .{Position{ .x = 1, .y = 1 }},
    );

    try std.testing.expect(ecs.entityIsValid(entityPtr) == true);

    ecs.destroyEntity(entityPtr.entity);

    ecs.clearDestroyedEntitys();

    try std.testing.expect(ecs.entityIsValid(entityPtr) == false);

    const entityPtr2 = ecs.createEntity(
        .{ .components = &[_]type{Position}, .tags = null },
        .{Position{ .x = 1, .y = 1 }},
    );

    try std.testing.expect(ecs.entityIsValid(entityPtr2) == true);

    try std.testing.expect(entityPtr.entity.value() == entityPtr2.entity.value());
    try std.testing.expect(entityPtr.generation.value() == entityPtr2.generation.value() - 1);
}

test "Iterating over a component" {
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position}, .tags = null },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = null },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{}, .tags = null }).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.buffers.len == 3);
    try std.testing.expect(iterator.buffers[0].len == 100);
    try std.testing.expect(iterator.buffers[1].len == 100);
    try std.testing.expect(iterator.buffers[2].len == 100);

    while (iterator.next()) |position| {
        try std.testing.expect(position.x == 1);
        try std.testing.expect(position.y == 1);
        position.x = 5;
        position.y = 2;
    }

    iterator.reset();

    while (iterator.next()) |position| {
        try std.testing.expect(position.x == 5);
        try std.testing.expect(position.y == 2);
    }

    var iterator2: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{}, .tags = &[_]type{Tag} }).?;
    defer iterator2.deinit();

    try std.testing.expect(iterator2.buffers.len == 1);
    try std.testing.expect(iterator2.buffers[0].len == 100);

    while (iterator2.next()) |position| {
        try std.testing.expect(position.x == 5);
        try std.testing.expect(position.y == 2);
    }
}

test "Iterating over multiple components" {
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position}, .tags = null },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
            .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = null },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: TupleIterator(&[_]type{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &[_]type{ Position, Collider }, .tags = null },
        .{ .components = &[_]type{}, .tags = null },
    ).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.tupleOfBuffers[0].len == 1);
    try std.testing.expect(iterator.tupleOfBuffers[0][0].len == 100);

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 6);
        try std.testing.expect(components[0].y == 5);
        components[0].x = 7;
        components[0].y = 7;
    }

    var iterator2: TupleIterator(&[_]type{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &[_]type{ Position, Collider }, .tags = null },
        .{ .components = &[_]type{}, .tags = null },
    ).?;
    defer iterator2.deinit();

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 7);
        try std.testing.expect(components[0].y == 7);
    }
}
