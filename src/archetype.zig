const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;

const Entity = @import("entity.zig").Entity;
const IndexType = @import("entity.zig").IndexType;
const ErasedArrayList = @import("erasedArrayList.zig").ErasedArray;

const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;

const Allocator = std.mem.Allocator;

const ComponentRow = enum(u16) { _ };

pub const Archetype = struct {
    bitset: Bitset,
    sparse: [MAX_COMPONENTS]u8,
    dense: std.ArrayListUnmanaged(ErasedArrayList),

    rowIdToComponentRow: std.AutoHashMapUnmanaged(IndexType, ComponentRow),
    componentRowTorowId: std.AutoHashMapUnmanaged(ComponentRow, IndexType),

    /// Transfers all of entity's components to a new archetype and adds a new component
    pub fn initTransfer(
        self: *Archetype,
        entity: Entity,
        row: IndexType,
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

    /// Transfer entity's components to other archetype and adding one component
    pub fn transferAdd(
        self: *Archetype,
        other: *Archetype,
        row: IndexType,
        comptime T: type,
        component: T,
        id: Component,
        allocator: std.mem.Allocator,
    ) void {
        for (self.dense.items) |list| {
            try list.transfer(&other.dense.items[other.sparse[list.id]], allocator);
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

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
