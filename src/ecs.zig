const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const EntityType = @import("entity.zig").EntityType;
const ArchetypeType = @import("entity.zig").ArchetypeType;
const FatPointer = @import("entity.zig").FatPointer;
const SlimPointer = @import("entity.zig").SlimPointer;

const EntityManager = @import("entityManager.zig").EntityManager;

const ComponentManager = @import("componentManager.zig").ComponentManager;
const ComponentType = @import("componentManager.zig").ComponentType;
const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const Row = @import("archetype.zig").Row;
const ErasedArray = @import("erasedArray.zig").ErasedArray;

const iterator = @import("iterator.zig");

pub const Ecs = struct {
    entityManager: EntityManager,
    componentManager: ComponentManager,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Ecs {
        return Ecs{
            .entityManager = EntityManager.init,
            .componentManager = ComponentManager.init,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Ecs) void {
        self.entityManager.deinit(self.allocator);
        self.componentManager.deinit(self.allocator);
    }

    pub fn createEntity(self: *Ecs, comptime T: type, componets: T) SlimPointer {
        switch (@typeInfo(T)) {
            .@"struct" => |@"struct"| {
                if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
                const bitset = self.componentManager.getBitsetForTuple(T, self.allocator);

                // Get new entity unused or new one.
                const slimPointer: SlimPointer = self.entityManager.getNewEntity();

                if (self.entityManager.archetypeMap.get(bitset)) |archetypeId| {
                    const archetype: *Archetype = &self.entityManager.archetypes.items[archetypeId.value()];

                    inline for (componets, 0..) |component, i| {
                        const componentId = self.componentManager.hashMap.get(ULandType.getHash(@"struct".fields[i].type)).?;
                        var array: *std.ArrayListUnmanaged(@"struct".fields[i].type) = archetype.componentArrays.items[archetype.componentMap.get(componentId).?].cast(@"struct".fields[i].type);

                        array.append(self.allocator, component) catch unreachable;
                    }

                    archetype.entityToRowMap.put(self.allocator, slimPointer.entity, Row.make(archetype.components)) catch unreachable;
                    archetype.rowToEntityMap.put(self.allocator, Row.make(archetype.components), slimPointer.entity) catch unreachable;
                    archetype.components += 1;

                    self.entityManager.entityMap.put(self.allocator, slimPointer.entity, FatPointer{ .archetype = archetypeId, .generation = slimPointer.generation }) catch unreachable;

                    return slimPointer;
                } else {
                    self.entityManager.archetypes.append(self.allocator, Archetype{
                        .bitset = bitset,
                        .componentArrays = .empty,
                        .components = 0,

                        .entityToRowMap = std.AutoHashMapUnmanaged(EntityType, Row).empty,
                        .rowToEntityMap = std.AutoHashMapUnmanaged(Row, EntityType).empty,
                        .componentMap = .empty,
                    }) catch unreachable;

                    const archetype: *Archetype = &self.entityManager.archetypes.items[self.entityManager.archetypes.items.len - 1];
                    const archetypeId = ArchetypeType.make(@intCast(self.entityManager.archetypes.items.len - 1));

                    inline for (componets, 0..) |component, i| {
                        const componentId = self.componentManager.hashMap.get(ULandType.getHash(@"struct".fields[i].type)).?;
                        var array: ErasedArray = ErasedArray.init(@"struct".fields[i].type, componentId, self.allocator) catch unreachable;
                        array.cast(@"struct".fields[i].type).append(self.allocator, component) catch unreachable;
                        archetype.componentArrays.append(self.allocator, array) catch unreachable;
                        archetype.componentMap.put(self.allocator, componentId, @intCast(archetype.componentArrays.items.len - 1)) catch unreachable;
                    }

                    self.entityManager.archetypeMap.put(self.allocator, bitset, archetypeId) catch unreachable;

                    archetype.entityToRowMap.put(self.allocator, slimPointer.entity, Row.make(archetype.components)) catch unreachable;
                    archetype.rowToEntityMap.put(self.allocator, Row.make(archetype.components), slimPointer.entity) catch unreachable;
                    archetype.components += 1;

                    self.entityManager.entityMap.put(self.allocator, slimPointer.entity, FatPointer{ .archetype = archetypeId, .generation = slimPointer.generation }) catch unreachable;

                    return slimPointer;
                }
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }

    /// SlimPointer becomes invalid!
    pub fn destroyEntity(self: *Ecs, slimPointer: SlimPointer) void {
        const fatPointer = self.entityManager.entityMap.get(slimPointer.entity).?;
        std.debug.assert(slimPointer.generation == fatPointer.generation);

        const archetype: *Archetype = &self.entityManager.archetypes.items[fatPointer.archetype.value()];

        const row = archetype.entityToRowMap.get(slimPointer.entity).?;

        for (archetype.componentArrays.items) |*array| {
            array.swapRemove(array, row, self.allocator);
        }

        if (archetype.components == 1) {
            archetype.entityToRowMap.clearAndFree(self.allocator);
            archetype.rowToEntityMap.clearAndFree(self.allocator);
        } else {
            const entity = archetype.rowToEntityMap.get(Row.make(archetype.components - 1)).?;

            _ = archetype.rowToEntityMap.remove(Row.make(archetype.components - 1));
            _ = archetype.entityToRowMap.remove(slimPointer.entity);

            archetype.entityToRowMap.put(self.allocator, entity, row) catch unreachable;
            archetype.rowToEntityMap.put(self.allocator, row, entity) catch unreachable;
        }

        archetype.components -= 1;

        _ = self.entityManager.entityMap.swapRemove(slimPointer.entity);
        self.entityManager.unused.append(self.allocator, slimPointer) catch unreachable;
    }

    pub fn getEntityComponent(self: *Ecs, slimPointer: SlimPointer, comptime T: type) *T {
        const fatPointer = self.entityManager.entityMap.get(slimPointer.entity).?;
        std.debug.assert(slimPointer.generation == fatPointer.generation);

        const archetype: *Archetype = &self.entityManager.archetypes.items[fatPointer.archetype.value()];

        const componentId = self.componentManager.hashMap.get(ULandType.getHash(T)).?;
        const componentArrayIndex: u32 = archetype.componentMap.get(componentId).?;
        const row: Row = archetype.entityToRowMap.get(slimPointer.entity).?;

        return &archetype.componentArrays.items[componentArrayIndex].cast(T).items[row.value()];
    }

    /// Gets all archetypes that have all of the components in the tuple and returns them as iterators.
    /// Remember to call deinit on the iterator.
    pub fn getComponentIterators(self: *Ecs, comptime included: type, comptime excluded: type) ?iterator.Iterator(included) {
        const includedStruct = getTupleInfo(included, false);
        const excludedStruct = getTupleInfo(excluded, true);

        var wanted: Bitset = Bitset.initEmpty();
        var notWanted: Bitset = Bitset.initEmpty();

        inline for (excludedStruct.fields) |field| {
            if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |componentId| notWanted.set(componentId.value());
        }

        var tuple: iterator.TupleOfArrayLists(included) = undefined;

        inline for (includedStruct.fields, 0..) |field, i| {
            tuple[i] = .empty;

            if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |componentId| wanted.set(componentId.value()) else return null;
        }

        if (!wanted.intersectWith(notWanted).eql(Bitset.initEmpty())) return null;

        for (self.entityManager.archetypes.items) |*archetype| {
            if (wanted.intersectWith(archetype.bitset).eql(wanted) and notWanted.intersectWith(archetype.bitset).eql(Bitset.initEmpty()) and archetype.components > 0) {
                inline for (includedStruct.fields, 0..) |field, i| {
                    const componentId = self.componentManager.hashMap.get(ULandType.getHash(field.type)).?;
                    tuple[i].append(self.allocator, archetype.componentArrays.items[archetype.componentMap.get(componentId).?].cast(field.type).items) catch unreachable;
                }
            }
        }

        if (tuple[0].items.len == 0) return null;

        var tBuffers: iterator.TupleOfBuffers(included) = undefined;
        inline for (0..includedStruct.fields.len) |i| tBuffers[i] = tuple[i].toOwnedSlice(self.allocator) catch unreachable;

        return iterator.Iterator(included).init(tBuffers, self.allocator);
    }

    fn getTupleInfo(comptime T: type, comptime emptyIsTuple: bool) std.builtin.Type.Struct {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (info.is_tuple or (emptyIsTuple and info.fields.len == 0)) return info;

                @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or it was a tuple, but was empty");
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }
};
