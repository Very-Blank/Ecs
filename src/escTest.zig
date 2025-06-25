const std = @import("std");
const Ecs = @import("ecs.zig").Ecs;
const ECS = @import("ecs.zig").ECS;
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
    switch (@typeInfo(ECS(false))) {
        .@"struct" => |@"struct"| {
            inline for (@"struct".fields) |field| {
                std.debug.print("{s}\n", .{field.name});
            }
        },
        else => {},
    }

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

test "Creating singleton with component requirements" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create singletons with different component requirements
    const cameraSingleton = ecs.createSingleton(struct { Position, Velocity });
    const inputSingleton = ecs.createSingleton(struct { Position });
    const colliderSingleton = ecs.createSingleton(struct { Collider, Position, Velocity });

    // Should create different singleton IDs
    try std.testing.expect(cameraSingleton.value() != inputSingleton.value());
    try std.testing.expect(inputSingleton.value() != colliderSingleton.value());
}

test "Registering entity with matching components succeeds" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entity with Position and Velocity
    const entity = ecs.createEntity(struct { Position, Velocity }, .{
        Position{ .x = 10, .y = 20 },
        Velocity{ .x = 5, .y = 8 },
    });

    // Create singleton that requires Position and Velocity
    const singleton = ecs.createSingleton(struct { Position, Velocity });

    // Registration should succeed
    try ecs.registerSingletonToEntity(singleton, entity);

    // Should be able to get the entity back
    try std.testing.expectEqual(entity, ecs.getSingletonsEntity(singleton).?);
}

test "Registering entity with extra components succeeds" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entity with more components than required
    const entity = ecs.createEntity(struct { Position, Velocity, Collider }, .{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 3, .y = 4 },
        Collider{ .x = 5, .y = 6 },
    });

    // Singleton only requires Position and Velocity
    const singleton = ecs.createSingleton(struct { Position, Velocity });

    // Registration should succeed (entity has required components plus extras)
    try ecs.registerSingletonToEntity(singleton, entity);

    try std.testing.expectEqual(entity, ecs.getSingletonsEntity(singleton).?);
}

test "Registering entity with missing components fails" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entity with only Position
    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 2 },
    });

    // Singleton requires both Position and Velocity
    const singleton = ecs.createSingleton(struct { Position, Velocity });

    // Registration should fail
    try std.testing.expectError(error.EntityNotMatchingRequirments, ecs.registerSingletonToEntity(singleton, entity));

    // Singleton should still return null (not registered)
    try std.testing.expectEqual(null, ecs.getSingletonsEntity(singleton));
}

test "Single component requirement works" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 100, .y = 200 },
    });

    const singleton = ecs.createSingleton(struct { Position });

    try ecs.registerSingletonToEntity(singleton, entity);
    try std.testing.expectEqual(entity, ecs.getSingletonsEntity(singleton).?);
}

test "Failed registration doesn't affect existing registration" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create two entities - one valid, one invalid
    const validEntity = ecs.createEntity(struct { Position, Velocity }, .{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 3, .y = 4 },
    });

    const invalidEntity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 5, .y = 6 },
    });

    const singleton = ecs.createSingleton(struct { Position, Velocity });

    // Register valid entity first
    try ecs.registerSingletonToEntity(singleton, validEntity);
    try std.testing.expectEqual(validEntity, ecs.getSingletonsEntity(singleton).?);

    // Try to register invalid entity - should fail
    try std.testing.expectError(error.EntityNotMatchingRequirments, ecs.registerSingletonToEntity(singleton, invalidEntity));

    // Original registration should still be intact
    try std.testing.expectEqual(validEntity, ecs.getSingletonsEntity(singleton).?);
}

test "Multiple singletons with different requirements" {
    var ecs: Ecs = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entities with different component combinations
    const positionEntity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 1 },
    });

    const movingEntity = ecs.createEntity(struct { Position, Velocity }, .{
        Position{ .x = 2, .y = 2 },
        Velocity{ .x = 1, .y = 1 },
    });

    const collidingEntity = ecs.createEntity(struct { Position, Collider }, .{
        Position{ .x = 3, .y = 3 },
        Collider{ .x = 1, .y = 1 },
    });

    // Create singletons with different requirements
    const positionSingleton = ecs.createSingleton(struct { Position });
    const movingSingleton = ecs.createSingleton(struct { Position, Velocity });
    const collidingSingleton = ecs.createSingleton(struct { Position, Collider });

    // Register appropriate entities
    try ecs.registerSingletonToEntity(positionSingleton, positionEntity);
    try ecs.registerSingletonToEntity(movingSingleton, movingEntity);
    try ecs.registerSingletonToEntity(collidingSingleton, collidingEntity);

    // Verify all registrations
    try std.testing.expectEqual(positionEntity, ecs.getSingletonsEntity(positionSingleton).?);
    try std.testing.expectEqual(movingEntity, ecs.getSingletonsEntity(movingSingleton).?);
    try std.testing.expectEqual(collidingEntity, ecs.getSingletonsEntity(collidingSingleton).?);

    // Test invalid registrations
    try std.testing.expectError(error.EntityNotMatchingRequirments, ecs.registerSingletonToEntity(movingSingleton, positionEntity));
    try std.testing.expectError(error.EntityNotMatchingRequirments, ecs.registerSingletonToEntity(collidingSingleton, movingEntity));
}
