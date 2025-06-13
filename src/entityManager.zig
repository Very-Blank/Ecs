const std = @import("std");
const Archetype = @import("archetype.zig").Archetype;

const Entity = @import("entity.zig").Entity;
const Unused = @import("entity.zig").Unused;
const ArchetypeId = @import("entity.zig").ArchetypeId;
const Pointer = @import("entity.zig").Pointer;
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;

const MAX_ENTITIES = 5000;

const Allocator = std.mem.Allocator;

const EntityManager = struct {
    unused: std.ArrayListUnmanaged(Entity),
    archetypes: std.ArrayListUnmanaged(Archetype),

    entityIds: std.AutoHashMapUnmanaged(Entity, Pointer),
    archetypeIds: std.AutoHashMapUnmanaged(Bitset, ArchetypeId),

    len: u32,

    pub fn addComponentToUnused(
        self: *EntityManager,
        unused: Unused,
        comptime T: type,
        component: T,
        id: Component,
        allocator: Allocator,
    ) Entity {
        var newBitset: Bitset = Bitset.initEmpty();
        newBitset.set(id.value());

        if (self.archetypeIds.get(newBitset)) |newArchetypeId| {
            const newArchetype = self.archetypes.items[newArchetypeId];
        } else {
            var newArhcetype: Archetype = Archetype.initNew(entity, T, component, id, allocator);
            self.archetypes.append();
        }
    }

    pub fn addComponent(
        self: *EntityManager,
        entity: Entity,
        comptime T: type,
        component: T,
        id: Component,
        allocator: Allocator,
    ) !void {
        const pointer: Pointer = self.getPointer(entity).?;
        const oldArchetype: Archetype = self.archetypes.items[pointer.archetype];
        var newBitset: Bitset = oldArchetype.bitset;
        newBitset.set(id.value());

        if (self.archetypeIds.get(newBitset)) |newArchetypeId| {
            const newArchetype = self.archetypes.items[newArchetypeId];
        } else {}
    }

    pub fn findUnused() Entity {}

    // pub fn newEntity(self: *EntityManager, allocator: Allocator) !Unused {
    //     if (self.unused.items.len > 0) {
    //         return self.unused.items[self.unused.get(self.unused.len - 1)];
    //     }
    //
    //     try self.unused.append(allocator, .{ .id = self.len, .generation = 0 });
    //     self.len += 1;
    //     return .{ .id = self.len, .generation = 0 };
    // }

    pub inline fn getPointer(self: *EntityManager, entity: Entity) ?Pointer {
        std.debug.assert(entity.value() < self.len);
        return self.entitys.get(entity.value());
    }
};
