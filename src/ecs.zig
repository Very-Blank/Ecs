const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const EntityType = @import("entity.zig").EntityType;
const FatPointer = @import("entity.zig").FatPointer;
const SlimPointer = @import("entity.zig").SlimPointer;

const EntityManager = @import("entityManager.zig").EntityManager;

const ComponentManager = @import("componentManager.zig").ComponentManager;
const ComponentType = @import("componentManager.zig").ComponentType;
const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const Row = @import("archetype.zig").Row;

const ErasedArray = @import("erasedArray.zig").ErasedArray;

const SingletonManager = @import("singletonManager.zig").SingletonManager;
const SingletonType = @import("singletonManager.zig").SingletonType;

const EventManager = @import("eventManager.zig").EventManager;

const iterator = @import("iterator.zig");

pub fn Ecs(comptime events: type) type {
    const eventsEnabled: bool = env: switch (@typeInfo(events)) {
        .@"struct" => |info| {
            if (info.is_tuple) break :env true;
            if (info.fields.len == 0) break :env false;

            @compileError("Unexpected type, was given " ++ @typeName(events) ++ ". Expected tuple.");
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(events) ++ ". Expected tuple."),
    };

    return struct {
        entityManager: EntityManager,
        componentManager: ComponentManager,
        singletonManager: SingletonManager,
        eventManager: if (eventsEnabled) EventManager(events) else void,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .entityManager = EntityManager.init,
                .componentManager = ComponentManager.init,
                .singletonManager = SingletonManager.init,
                .eventManager = if (eventsEnabled) EventManager(events).init(allocator) catch unreachable,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.entityManager.deinit(self.allocator);
            self.componentManager.deinit(self.allocator);
            self.singletonManager.deinit(self.allocator);
            if (eventsEnabled) self.eventManager.deinit(self.allocator);
        }

        pub fn createEntity(self: *Self, comptime T: type, componets: T) SlimPointer {
            switch (@typeInfo(T)) {
                .@"struct" => |@"struct"| {
                    if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");

                    var bitset = Bitset.initEmpty();
                    inline for (@"struct".fields) |field| {
                        if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |id| {
                            if (bitset.isSet(id.value())) unreachable;
                            bitset.set(id.value());
                        } else {
                            bitset.set(self.componentManager.registerComponent(self.allocator, field.type).value());
                        }
                    }

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

                            .entityToRowMap = std.AutoArrayHashMapUnmanaged(EntityType, Row).empty,
                            .rowToEntityMap = std.AutoArrayHashMapUnmanaged(Row, EntityType).empty,
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

        /// This queues up the entity to be destroyed
        pub fn destroyEntity(self: *Self, entity: SlimPointer) void {
            self.entityManager.destroyed.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.entityManager.destroyed.items) |destroyed| {
                self.deleteEntity(destroyed);
            }

            self.entityManager.destroyed.clearAndFree(self.allocator);
        }

        /// SlimPointer becomes invalid!
        fn deleteEntity(self: *Self, slimPointer: SlimPointer) void {
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

                _ = archetype.rowToEntityMap.swapRemove(Row.make(archetype.components - 1));
                _ = archetype.entityToRowMap.swapRemove(slimPointer.entity);

                archetype.entityToRowMap.put(self.allocator, entity, row) catch unreachable;
                archetype.rowToEntityMap.put(self.allocator, row, entity) catch unreachable;
            }

            archetype.components -= 1;

            _ = self.entityManager.entityMap.swapRemove(slimPointer.entity);
            self.entityManager.unused.append(self.allocator, slimPointer) catch unreachable;
        }

        pub fn entityIsValid(self: *Self, slimPointer: SlimPointer) bool {
            if (self.entityManager.entityMap.get(slimPointer.entity)) |fatPointer| {
                return slimPointer.generation == fatPointer.generation;
            }

            return false;
        }

        pub fn entityHasComponent(self: *Self, slimPointer: SlimPointer, comptime T: type) bool {
            const fatPointer = self.entityManager.entityMap.get(slimPointer.entity).?;
            std.debug.assert(slimPointer.generation == fatPointer.generation);

            const archetype: *Archetype = &self.entityManager.archetypes.items[fatPointer.archetype.value()];
            if (self.componentManager.hashMap.get(ULandType.getHash(T))) |componentId| {
                return archetype.componentMap.contains(componentId);
            }

            return false;
        }

        pub fn getEntityComponent(self: *Self, slimPointer: SlimPointer, comptime T: type) *T {
            const fatPointer = self.entityManager.entityMap.get(slimPointer.entity).?;
            std.debug.assert(slimPointer.generation == fatPointer.generation);

            const archetype: *Archetype = &self.entityManager.archetypes.items[fatPointer.archetype.value()];

            const componentId = self.componentManager.hashMap.get(ULandType.getHash(T)).?;
            const componentArrayIndex: u32 = archetype.componentMap.get(componentId).?;
            const row: Row = archetype.entityToRowMap.get(slimPointer.entity).?;

            return &archetype.componentArrays.items[componentArrayIndex].cast(T).items[row.value()];
        }

        fn getReturnType(comptime T: type) type {
            switch (@typeInfo(T)) {
                .@"struct" => |info| {
                    if (!info.is_tuple or info.fields.len == 0) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or it was a tuple, but was empty");

                    if (info.fields.len == 1) {
                        return iterator.Iterator(info.fields[0].type);
                    } else {
                        return iterator.TupleIterator(T);
                    }
                },
                else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
            }
        }

        /// Gets all archetypes that have all of the components in the tuple and returns them as iterators.
        /// Remember to call deinit on the iterator.
        pub fn getComponentIterators(self: *Self, comptime included: type, comptime excluded: type) ?getReturnType(included) {
            const includedStruct = getTupleInfo(included, false);
            const excludedStruct = getTupleInfo(excluded, true);

            var wanted: Bitset = Bitset.initEmpty();
            var notWanted: Bitset = Bitset.initEmpty();

            inline for (excludedStruct.fields) |field| {
                if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |componentId| notWanted.set(componentId.value());
            }

            if (includedStruct.fields.len > 1) {
                var tuple: iterator.TupleOfArrayLists(included) = undefined;

                inline for (includedStruct.fields, 0..) |field, i| {
                    tuple[i] = .empty;

                    if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |componentId| wanted.set(componentId.value()) else return null;
                }

                if (!wanted.intersectWith(notWanted).eql(Bitset.initEmpty())) unreachable;

                var entities = std.ArrayListUnmanaged([]EntityType).empty;

                for (self.entityManager.archetypes.items) |*archetype| {
                    if (wanted.intersectWith(archetype.bitset).eql(wanted) and notWanted.intersectWith(archetype.bitset).eql(Bitset.initEmpty()) and archetype.components > 0) {
                        inline for (includedStruct.fields, 0..) |field, i| {
                            const componentId = self.componentManager.hashMap.get(ULandType.getHash(field.type)).?;
                            tuple[i].append(self.allocator, archetype.componentArrays.items[archetype.componentMap.get(componentId).?].cast(field.type).items) catch unreachable;
                        }

                        entities.append(self.allocator, archetype.entityToRowMap.keys()) catch unreachable;
                    }
                }

                if (tuple[0].items.len == 0) return null;

                var tBuffers: iterator.TupleOfBuffers(included) = undefined;
                inline for (0..includedStruct.fields.len) |i| tBuffers[i] = tuple[i].toOwnedSlice(self.allocator) catch unreachable;

                return iterator.TupleIterator(included).init(tBuffers, entities.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
            } else {
                var list = std.ArrayListUnmanaged([]includedStruct.fields[0].type).empty;
                if (self.componentManager.hashMap.get(ULandType.getHash(includedStruct.fields[0].type))) |componentId| wanted.set(componentId.value()) else return null;

                if (!wanted.intersectWith(notWanted).eql(Bitset.initEmpty())) unreachable;

                var entities = std.ArrayListUnmanaged([]EntityType).empty;

                for (self.entityManager.archetypes.items) |*archetype| {
                    if (wanted.intersectWith(archetype.bitset).eql(wanted) and notWanted.intersectWith(archetype.bitset).eql(Bitset.initEmpty()) and archetype.components > 0) {
                        const componentId = self.componentManager.hashMap.get(ULandType.getHash(includedStruct.fields[0].type)).?;
                        list.append(self.allocator, archetype.componentArrays.items[archetype.componentMap.get(componentId).?].cast(includedStruct.fields[0].type).items) catch unreachable;
                        entities.append(self.allocator, archetype.entityToRowMap.keys()) catch unreachable;
                    }
                }

                if (list.items.len == 0) return null;

                return iterator.Iterator(includedStruct.fields[0].type).init(list.toOwnedSlice(self.allocator) catch unreachable, entities.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
            }
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

        pub fn createSingleton(self: *Self, comptime T: type) SingletonType {
            const @"struct" = getTupleInfo(T, false);
            var bitset = Bitset.initEmpty();

            inline for (@"struct".fields) |field| {
                if (self.componentManager.hashMap.get(ULandType.getHash(field.type))) |id| {
                    if (bitset.isSet(id.value())) unreachable;
                    bitset.set(id.value());
                } else {
                    bitset.set(self.componentManager.registerComponent(self.allocator, field.type).value());
                }
            }

            self.singletonManager.singletons.append(self.allocator, bitset) catch unreachable;
            return SingletonType.make(@intCast(self.singletonManager.singletons.items.len - 1));
        }

        pub fn registerSingletonToEntity(self: *Self, singleton: SingletonType, slimPointer: SlimPointer) !void {
            const fatPointer = self.entityManager.entityMap.get(slimPointer.entity).?;
            std.debug.assert(slimPointer.generation == fatPointer.generation);
            std.debug.assert(singleton.value() < self.singletonManager.singletons.items.len);

            const archetype: *Archetype = &self.entityManager.archetypes.items[fatPointer.archetype.value()];

            const bitset = self.singletonManager.singletons.items[singleton.value()];

            if (archetype.bitset.intersectWith(bitset).eql(bitset)) {
                self.singletonManager.singletonToEntityMap.put(self.allocator, singleton, slimPointer) catch unreachable;
            } else {
                return error.EntityNotMatchingRequirments;
            }
        }

        pub fn getSingletonsEntity(self: *Self, singleton: SingletonType) ?SlimPointer {
            if (self.singletonManager.singletonToEntityMap.get(singleton)) |entity| {
                if (self.entityIsValid(entity)) return entity else {
                    _ = self.singletonManager.singletonToEntityMap.remove(singleton);
                    return null;
                }
            }

            return null;
        }

        pub fn getEntityEvent(self: *Self, comptime T: type, entity: SlimPointer) ?T {
            if (!eventsEnabled) @compileError("Self has no event system enabled. Cannot get event of type " ++ @typeName(T));

            std.debug.assert(self.entityIsValid(entity));
            for (self.eventManager.keys, 0..) |key, i| {
                if (key == ULandType.getHash(T)) {
                    const eventMap = self.eventManager.events[i].cast(T);
                    return eventMap.get(entity.entity);
                }
            }

            unreachable; //User put bs type
        }

        pub fn addEntityEvent(self: *Self, comptime T: type, event: T, entity: EntityType) void {
            if (!eventsEnabled) @compileError("Self has no event system enabled.");
            std.debug.assert(self.entityManager.entityMap.get(entity) != null);

            for (self.eventManager.keys, 0..) |key, i| {
                if (key == ULandType.getHash(T)) {
                    const eventMap = self.eventManager.events[i].cast(T);
                    eventMap.put(self.allocator, entity, event) catch unreachable;

                    return;
                }
            }

            unreachable; //User put bs type
        }

        pub fn clearEntityEvents(self: *Self) void {
            if (!eventsEnabled) @compileError("Self has no event system enabled.");
            for (&self.eventManager.events) |*event| {
                event.clear(event, self.allocator);
            }
        }
    };
}
