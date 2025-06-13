const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;

const Entity = @import("entity.zig").Entity;
const Row = @import("entity.zig").Row;
const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList;

const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;

const Allocator = std.mem.Allocator;

pub const Archetype = struct {
    // when removing, swap the end and with the removing element, then pop the end and change the entity pointer for "old" end.
    entities: std.ArrayListUnmanaged(Entity),
    bitset: Bitset,
    sparse: [MAX_COMPONENTS]u8,
    dense: std.ArrayListUnmanaged(ErasedArrayList),

    /// Transfers all of this archetypes components and adds a new one.
    pub fn initTransfer(
        self: *Archetype,
        entity: Entity,
        row: Row,
        comptime T: type,
        component: T,
        id: Component,
        allocator: Allocator,
    ) !Archetype {
        var entities: std.ArrayListUnmanaged(Entity) = .empty;
        try entities.append(allocator, entity);
        errdefer entities.deinit(allocator);

        var dense: std.ArrayListUnmanaged(ErasedArrayList) = try .initCapacity(allocator, self.dense.items.len + 1);
        errdefer dense.deinit(allocator);

        for (self.dense.items) |list| {
            try dense.append(allocator, try list.pop(row, allocator));
        }

        try dense.append(try ErasedArrayList.initWithElement(T, component, id, allocator));

        errdefer {
            for (dense.items) |list| {
                list.deinit(allocator);
            }

            dense.deinit(allocator);
        }

        var sparse: [MAX_COMPONENTS]u8 = self.sparse;
        sparse[id.value()] = dense.items.len - 1;

        var bitset: Bitset = self.bitset;
        bitset.set(id.value());

        return Archetype{
            .entities = try std.ArrayListUnmanaged(Entity).empty.append(allocator, entity),
            .bitset = self.bitset,
            .sparse = sparse,
            .dense = dense,
        };
    }

    pub fn initNew(
        entity: Entity,
        comptime T: type,
        component: T,
        id: Component,
        allocator: Allocator,
    ) !Archetype {
        var entities: std.ArrayListUnmanaged(Entity) = .empty;
        try entities.append(allocator, entity);
        errdefer entities.deinit(allocator);

        var bitset: Bitset = Bitset.initEmpty();
        bitset.set(id.value());

        var sparse: [MAX_COMPONENTS]u8 = .{0} ** MAX_COMPONENTS;
        sparse[id.value()] = 1;

        const list = try ErasedArrayList.initWithElement(T, component, id, allocator);
        errdefer list.deinit(allocator);

        return Archetype{
            .entities = entities,
            .bitset = bitset,
            .sparse = sparse,
            .dense = try std.ArrayListUnmanaged(ErasedArrayList).empty.append(allocator, list),
        };
    }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
