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

test "Creating and registering singletons" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create some entities
    const cameraEntity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 10, .y = 20 },
    });

    const inputEntity = ecs.createEntity(struct { Velocity }, .{
        Velocity{ .x = 5, .y = 8 },
    });

    // Create singletons
    const cameraSingleton = ecs.createSingleton();
    const inputSingleton = ecs.createSingleton();

    // Register entities to singletons
    ecs.registerSingletonToEntity(cameraSingleton, cameraEntity);
    ecs.registerSingletonToEntity(inputSingleton, inputEntity);

    // Test getting singleton entities
    try std.testing.expectEqual(cameraEntity, ecs.getSingletonsEntity(cameraSingleton).?);
    try std.testing.expectEqual(inputEntity, ecs.getSingletonsEntity(inputSingleton).?);
}

test "Singleton returns null for invalid entity" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entity and singleton
    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 2 },
    });

    const singleton = ecs.createSingleton();
    ecs.registerSingletonToEntity(singleton, entity);

    // Verify entity is registered
    try std.testing.expectEqual(entity, ecs.getSingletonsEntity(singleton).?);

    // Destroy the entity
    ecs.destroyEntity(entity);

    // Singleton should now return null
    try std.testing.expectEqual(null, ecs.getSingletonsEntity(singleton));
}

test "Multiple singletons with unique IDs" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create multiple singletons
    const singleton1 = ecs.createSingleton();
    const singleton2 = ecs.createSingleton();
    const singleton3 = ecs.createSingleton();

    // Singletons should have different values
    try std.testing.expect(singleton1.value() != singleton2.value());
    try std.testing.expect(singleton2.value() != singleton3.value());
    try std.testing.expect(singleton1.value() != singleton3.value());

    // Should be sequential
    try std.testing.expectEqual(0, singleton1.value());
    try std.testing.expectEqual(1, singleton2.value());
    try std.testing.expectEqual(2, singleton3.value());
}

test "Unregistered singleton returns null" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    const singleton = ecs.createSingleton();

    // Should return null since no entity is registered
    try std.testing.expectEqual(null, ecs.getSingletonsEntity(singleton));
}

test "Reassigning singleton to different entity" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create two entities
    const entity1 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 1 },
    });

    const entity2 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 2, .y = 2 },
    });

    const singleton = ecs.createSingleton();

    // Register first entity
    ecs.registerSingletonToEntity(singleton, entity1);
    try std.testing.expectEqual(entity1, ecs.getSingletonsEntity(singleton).?);

    // Reassign to second entity
    ecs.registerSingletonToEntity(singleton, entity2);
    try std.testing.expectEqual(entity2, ecs.getSingletonsEntity(singleton).?);
}
