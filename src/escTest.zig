const std = @import("std");
const Ecs = @import("ecs.zig").Ecs;
const Row = @import("archetype.zig").Row;
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
    defer ecs.deinit();

    const entity1 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 3 },
    });

    const entity2 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 4, .y = 1 },
    });

    ecs.destroyEntity(entity1);
    ecs.clearDestroyedEntitys();

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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
    defer ecs.deinit();

    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 100, .y = 200 },
    });

    const singleton = ecs.createSingleton(struct { Position });

    try ecs.registerSingletonToEntity(singleton, entity);
    try std.testing.expectEqual(entity, ecs.getSingletonsEntity(singleton).?);
}

test "Failed registration doesn't affect existing registration" {
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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
    var ecs: Ecs(struct {}) = .init(std.testing.allocator);
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

const HitEvent = struct { damage: f32 };

test "Testing event system" {
    var ecs: Ecs(struct { HitEvent }) = .init(std.testing.allocator);
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

    // Test adding an event to an entity
    ecs.addEntityEvent(HitEvent, .{ .damage = 0.5 }, positionEntity.entity);

    // Test retrieving the event
    const event: ?[]HitEvent = ecs.getEntityEvent(HitEvent, positionEntity.entity);
    try std.testing.expect(event != null);
    try std.testing.expectEqual(0.5, event.?[0].damage);

    // Test that other entities don't have this event
    const movingEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, movingEntity.entity);
    try std.testing.expectEqual(null, movingEvent);

    const collidingEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, collidingEntity.entity);
    try std.testing.expectEqual(null, collidingEvent);

    // Test adding events to multiple entities
    ecs.addEntityEvent(HitEvent, .{ .damage = 1.0 }, movingEntity.entity);
    ecs.addEntityEvent(HitEvent, .{ .damage = 2.5 }, collidingEntity.entity);

    // Verify all entities have their respective events
    const positionEntityEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, positionEntity.entity);
    const movingEntityEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, movingEntity.entity);
    const collidingEntityEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, collidingEntity.entity);

    try std.testing.expect(positionEntityEvent != null);
    try std.testing.expect(movingEntityEvent != null);
    try std.testing.expect(collidingEntityEvent != null);

    try std.testing.expectEqual(0.5, positionEntityEvent.?[0].damage);
    try std.testing.expectEqual(1.0, movingEntityEvent.?[0].damage);
    try std.testing.expectEqual(2.5, collidingEntityEvent.?[0].damage);

    // Test overwriting an existing event
    ecs.addEntityEvent(HitEvent, .{ .damage = 10.0 }, positionEntity.entity);
    const updatedEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, positionEntity.entity);
    try std.testing.expect(updatedEvent != null);
    try std.testing.expectEqual(10.0, updatedEvent.?[1].damage);

    // Test clearing events
    ecs.clearEntityEvents();

    // Verify all events are cleared
    try std.testing.expectEqual(null, ecs.getEntityEvent(HitEvent, positionEntity.entity));
    try std.testing.expectEqual(null, ecs.getEntityEvent(HitEvent, movingEntity.entity));
    try std.testing.expectEqual(null, ecs.getEntityEvent(HitEvent, collidingEntity.entity));

    // Test adding events after clearing
    ecs.addEntityEvent(HitEvent, .{ .damage = 3.14 }, positionEntity.entity);
    const afterClearEvent: ?[]HitEvent = ecs.getEntityEvent(HitEvent, positionEntity.entity);
    try std.testing.expect(afterClearEvent != null);
    try std.testing.expectEqual(3.14, afterClearEvent.?[0].damage);
}

test "getCurrentEntity with iterator and event system" {
    var ecs: Ecs(struct { HitEvent }) = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create several entities with Position components
    const entity1 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 10, .y = 20 },
    });

    const entity2 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 30, .y = 40 },
    });

    const entity3 = ecs.createEntity(struct { Position }, .{
        Position{ .x = 50, .y = 60 },
    });

    // Get iterator for Position components
    var iterator: Iterator(Position) = ecs.getComponentIterators(struct { Position }, struct {}).?;
    defer iterator.deinit();

    var processedEntities: [3]EntityType = undefined;
    var count: usize = 0;

    // Iterate through entities and test getCurrentEntity
    while (iterator.next()) |position| {
        const currentEntity = iterator.getCurrentEntity();
        processedEntities[count] = currentEntity;

        // Add an event to the current entity based on its position
        const damage = @as(f32, @floatFromInt(position.x)) * 0.1;
        ecs.addEntityEvent(HitEvent, .{ .damage = damage }, currentEntity);

        count += 1;
        if (count > 10) return error.InfiniteLoop; // Safety check
    }

    // Verify we processed all 3 entities
    try std.testing.expectEqual(3, count);

    // Test that getCurrentEntity returns the last valid entity after iteration ends
    const lastEntity = iterator.getCurrentEntity();
    try std.testing.expectEqual(processedEntities[2], lastEntity);

    // Verify that all entities received the correct events
    const event1 = ecs.getEntityEvent(HitEvent, entity1.entity);
    const event2 = ecs.getEntityEvent(HitEvent, entity2.entity);
    const event3 = ecs.getEntityEvent(HitEvent, entity3.entity);

    try std.testing.expect(event1 != null);
    try std.testing.expect(event2 != null);
    try std.testing.expect(event3 != null);

    try std.testing.expectEqual(1.0, event1.?[0].damage); // 10 * 0.1
    try std.testing.expectEqual(3.0, event2.?[0].damage); // 30 * 0.1
    try std.testing.expectEqual(5.0, event3.?[0].damage); // 50 * 0.1

    // Verify that the processed entities match our created entities
    // Note: Order might vary depending on your archetype implementation
    var foundEntities = [_]bool{false} ** 3;
    for (processedEntities) |processed| {
        if (processed == entity1.entity) foundEntities[0] = true;
        if (processed == entity2.entity) foundEntities[1] = true;
        if (processed == entity3.entity) foundEntities[2] = true;
    }

    try std.testing.expect(foundEntities[0]);
    try std.testing.expect(foundEntities[1]);
    try std.testing.expect(foundEntities[2]);
}

test "getCurrentEntity with TupleIterator" {
    var ecs: Ecs(struct { HitEvent }) = .init(std.testing.allocator);
    defer ecs.deinit();

    // Create entities with Position and Velocity
    const entity1 = ecs.createEntity(struct { Position, Velocity }, .{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 10, .y = 20 },
    });

    const entity2 = ecs.createEntity(struct { Position, Velocity }, .{
        Position{ .x = 3, .y = 4 },
        Velocity{ .x = 30, .y = 40 },
    });

    // Get tuple iterator
    var tupleIterator: TupleIterator(struct { Position, Velocity }) = ecs.getComponentIterators(struct { Position, Velocity }, struct {}).?;
    defer tupleIterator.deinit();

    var count: usize = 0;
    var lastValidEntity: EntityType = undefined;

    // Iterate and use getCurrentEntity for each
    while (tupleIterator.next()) |components| {
        const currentEntity = tupleIterator.getCurrentEntity();
        lastValidEntity = currentEntity;

        // Create event based on velocity magnitude
        const velocityMagnitude = components.@"1".x + components.@"1".y; // Velocity x + y
        const damage = @as(f32, @floatFromInt(velocityMagnitude)) * 0.01;

        ecs.addEntityEvent(HitEvent, .{ .damage = damage }, currentEntity);

        count += 1;
        if (count > 10) return error.InfiniteLoop;
    }

    try std.testing.expectEqual(2, count);

    // Test getCurrentEntity after iteration ends
    const finalEntity = tupleIterator.getCurrentEntity();
    try std.testing.expectEqual(lastValidEntity, finalEntity);

    // Verify events were added correctly
    const event1 = ecs.getEntityEvent(HitEvent, entity1.entity);
    const event2 = ecs.getEntityEvent(HitEvent, entity2.entity);

    try std.testing.expect(event1 != null);
    try std.testing.expect(event2 != null);

    // entity1: velocity (10, 20) -> magnitude 30 -> damage 0.3
    // entity2: velocity (30, 40) -> magnitude 70 -> damage 0.7
    try std.testing.expectApproxEqRel(0.3, event1.?[0].damage, 0.001);
    try std.testing.expectApproxEqRel(0.7, event2.?[0].damage, 0.001);
}

test "getCurrentEntity before any iteration" {
    var ecs: Ecs(struct { HitEvent }) = .init(std.testing.allocator);
    defer ecs.deinit();

    const entity = ecs.createEntity(struct { Position }, .{
        Position{ .x = 1, .y = 1 },
    });

    var iterator: Iterator(Position) = ecs.getComponentIterators(struct { Position }, struct {}).?;
    defer iterator.deinit();

    // Now iterate once
    _ = iterator.next();
    const entityAfterFirstNext = iterator.getCurrentEntity();

    // The entity after first next should be our created entity
    try std.testing.expectEqual(entity.entity, entityAfterFirstNext);

    // Call next again (should return null since only one entity)
    try std.testing.expectEqual(null, iterator.next());

    // getCurrentEntity should still return the last valid entity
    const entityAfterNull = iterator.getCurrentEntity();
    try std.testing.expectEqual(entity.entity, entityAfterNull);
}
