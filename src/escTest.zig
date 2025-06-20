const std = @import("std");
const Ecs = @import("ecs.zig").Ecs;
const Row = @import("archetype.zig").Row;
const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("iterator.zig").TupleIterator;

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
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Position }, .{
            Position{ .x = 1, .y = 3 },
        });
    }

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Position, Velocity }, .{
            Position{ .x = 1, .y = 3 },
            Velocity{ .x = 1, .y = 3 },
        });
    }

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Velocity, Position }, .{
            Velocity{ .x = 1, .y = 3 },
            Position{ .x = 1, .y = 3 },
        });
    }

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Velocity, Position, Collider }, .{
            Velocity{ .x = 1, .y = 3 },
            Position{ .x = 1, .y = 3 },
            Collider{ .x = 1, .y = 3 },
        });
    }

    for (0..100) |_| {
        _ = ecs.createEntity(struct { Velocity }, .{
            Velocity{ .x = 1, .y = 3 },
        });
    }

    try std.testing.expectEqual(4, ecs.entityManager.archetypes.items.len);
    try std.testing.expectEqual(3, ecs.componentManager.components.items.len);
    try std.testing.expectEqual(1, ecs.entityManager.archetypes.items[0].bitset.mask);
    try std.testing.expectEqual(3, ecs.entityManager.archetypes.items[1].bitset.mask);
    try std.testing.expectEqual(7, ecs.entityManager.archetypes.items[2].bitset.mask);
    try std.testing.expectEqual(2, ecs.entityManager.archetypes.items[3].bitset.mask);

    try std.testing.expectEqual(null, ecs.getComponentIterators(struct { Collider }, struct { Position, Velocity }));

    var iterator: Iterator(Position) = ecs.getComponentIterators(struct { Position }, struct {}).?;
    defer iterator.deinit();

    var tupleIterator: TupleIterator(struct { Position, Velocity }) = ecs.getComponentIterators(struct { Position, Velocity }, struct {}).?;
    defer tupleIterator.deinit();

    var i: u64 = 0;
    while (iterator.next()) |value| {
        if (i > 500) return error.InfiniteLoop;
        i += 1;
        _ = value;
    }

    try std.testing.expectEqual(400, i);

    i = 0;
    while (tupleIterator.next()) |value| {
        if (i > 500) return error.InfiniteLoop;
        i += 1;
        _ = value;
    }

    try std.testing.expectEqual(300, i);
}

test "Removing an entity" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    const entity1 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 3 },
    });

    const entity2 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 4, .y = 1 },
    });

    ecs.destroyEntity(entity1);

    const position: *Position = ecs.getEntityComponent(entity2, Position);

    try std.testing.expectEqual(null, ecs.entityManager.archetypes.items[0].entityToRowMap.get(entity1.entity));
    try std.testing.expectEqual(entity2.entity, ecs.entityManager.archetypes.items[0].rowToEntityMap.get(Row.make(0)));
    try std.testing.expectEqual(Row.make(0), ecs.entityManager.archetypes.items[0].entityToRowMap.get(entity2.entity));

    try std.testing.expectEqual(4, position.x);
    try std.testing.expectEqual(1, position.y);
}

const StringAllocator = struct {
    value: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *StringAllocator) void {
        self.allocator.free(self.value);
    }
};

const StringNoAllocator = struct {
    value: []u8,

    pub fn deinit(self: *StringNoAllocator, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

const message = "hello";

test "Deinit a component" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    const string: StringAllocator = .{ .value = try std.testing.allocator.alloc(u8, 5), .allocator = std.testing.allocator };
    @memcpy(string.value, message);

    const entity1 = ecs.createEntity(struct { StringAllocator }, .{
        string,
    });

    const string2: StringNoAllocator = .{ .value = try std.testing.allocator.alloc(u8, 5) };
    @memcpy(string2.value, message);

    _ = ecs.createEntity(struct { StringNoAllocator }, .{
        string2,
    });

    ecs.destroyEntity(entity1);
}
