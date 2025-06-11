const std = @import("std");
const Archetype = @import("archetype.zig").Archetype;

const Entity = @import("entity.zig").Entity;
const Pointer = @import("entity.zig").Pointer;
const Bitset = @import("componentManager.zig").Bitset;

const MAX_ENTITIES = 5000;

const MultiList = std.MultiArrayList;
const List = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const EntityManager = struct {
    len: u32,
    unused: MultiList(Entity),
    archetypes: List(Archetype),
    entitys: HashMap(u32, Pointer),
    archebitset: HashMap(Bitset, u16),

    pub fn addComponentExistingE(self: *EntityManager, comptime T: type, component: T, entity: Entity, componentId: u32, allocator: Allocator) !void {
        var pointer = if (self.getPointer(entity)) |pointer| pointer else unreachable;
        const archetype: Archetype = self.archetypes.items[pointer.archetype];

        if (self.archebitset.get(archetype.bitset)) |index| {
            const tArchetype = self.archetypes.items[index];
            // pointer.row = tArchetype.components.entries.len;
            try tArchetype.components.get(componentId).?.append(T, component, allocator);
            const iterator = archetype.components.valueIterator();

            while (iterator.next()) |eList| {
                var tEList = tArchetype.components.get(eList.id).?;
                eList.transfer(&eList, &tEList, pointer.row, allocator);
            }

            //TOODO move all other components
        }
    }

    // pub fn addComponentUnused(bitset: ) !void {
    //
    // }

    pub fn newEntity(self: *EntityManager, allocator: Allocator) !Entity {
        if (self.unused.items.len > 0) {
            return self.unused.items[self.unused.get(self.unused.len - 1)];
        }

        try self.unused.append(allocator, .{ .id = self.len, .generation = 0 });
        self.len += 1;
        return .{ .id = self.len, .generation = 0 };
    }

    pub inline fn getPointer(self: *EntityManager, entity: Entity) ?Pointer {
        std.debug.assert(entity.id < self.len);
        return self.entitys.get(entity.id);
    }
};
