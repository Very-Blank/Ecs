const std = @import("std");
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;
const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;
const Entity = @import("entity.zig").Entity;

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();

const Allocator = std.mem.Allocator;

pub const Archetype = struct {
    // when removing, swap the end and with the removing element, then pop the end and change the entity pointer for "old" end.
    entities: std.ArrayListUnmanaged(Entity),
    bitset: Bitset,
    sparse: [MAX_COMPONENTS]u8,
    dense: std.ArrayListUnmanaged(ErasedArrayList),

    pub fn init(
        entity: Entity,
        bitset: Bitset,
        sparse: [MAX_COMPONENTS]u8,
        dense: std.ArrayListUnmanaged(ErasedArrayList),
        allocator: Allocator,
    ) !Archetype {
        var entities: std.ArrayListUnmanaged(Entity) = .empty;
        try entities.append(allocator, entity);
        return Archetype{
            .entities = entities,
            .bitset = bitset,
            .sparse = sparse,
            .dense = dense,
        };
    }

    pub fn initNew(
        entity: Entity,
        comptime T: type,
        component: T,
        componentId: Component,
        allocator: Allocator,
    ) !Archetype {
        var entities: std.ArrayListUnmanaged(Entity) = .empty;
        try entities.append(allocator, entity);
        errdefer entities.deinit(allocator);

        var bitset: Bitset = Bitset.initEmpty();
        bitset.set(componentId.value());

        var sparse: [MAX_COMPONENTS]u8 = .{0} ** MAX_COMPONENTS;
        sparse[componentId.value()] = 0;

        ErasedArrayList.init();

        return Archetype{
            .entities = entities,
            .bitset = bitset,
            .sparse = sparse,
            .dense = dense,
        };
    }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
