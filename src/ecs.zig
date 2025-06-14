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
const ErasedArray = @import("erasedArray.zig");

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

                const slimPointer: SlimPointer = self.entityManager.getNewEntity();

                var archetype: *Archetype = undefined;
                var archetypeId: ArchetypeType = undefined;

                // Get new entity unused or new one.
                if (self.entityManager.archetypeMap.get(bitset)) |id| {
                    archetypeId = id;
                    archetype = &self.entityManager.archetypes.items[archetypeId.value()];

                    inline for (componets, 0..) |component, i| {
                        const componentId = self.componentManager.hashMap.get(ULandType.getHash(@"struct".fields[i].type)).?;
                        var array: *std.ArrayListUnmanaged(@"struct".fields[i].type) = archetype.componentArrays.items[archetype.componentMap.get(componentId).?].cast(@"struct".fields[i].type);

                        array.append(self.allocator, component) catch unreachable;
                    }
                } else {
                    var componentMap: std.AutoHashMapUnmanaged(ComponentType, u32) = .empty;
                    var componentArrays: std.ArrayListUnmanaged(ErasedArray) = .empty;

                    inline for (componets, 0..) |component, i| {
                        const componentId = self.componentManager.hashMap.get(ULandType.getHash(@"struct".fields[i].type)).?;
                        var array: std.ArrayListUnmanaged(@"struct".fields[i].type) = .empty;
                        array.append(self.allocator, component) catch unreachable;
                        componentArrays.append(self.allocator, array) catch unreachable;
                        componentMap.put(self.allocator, componentId, componentArrays.items.len - 1) catch unreachable;
                    }

                    self.entityManager.archetypes.append(self.allocator, Archetype{
                        .bitset = bitset,
                        .componentArrays = componentArrays,
                        .components = 0,

                        .entityToRow = std.AutoHashMapUnmanaged(EntityType, Row).empty,
                        .rowToEntity = std.AutoHashMapUnmanaged(Row, EntityType).empty,
                        .componentToArray = componentMap,
                    }) catch unreachable;

                    archetypeId = Archetype.make(self.entityManager.archetypes.items - 1);
                    archetype = &self.entityManager.archetypes.items[archetypeId.value()];
                }

                archetype.entityToRow.put(self.allocator, slimPointer.entity, Row.make(archetype.components)) catch unreachable;
                archetype.rowToEntity.put(self.allocator, Row.make(archetype.components, slimPointer.entity)) catch unreachable;
                archetype.components += 1;

                self.entityManager.entityMap.put(self.allocator, slimPointer.entity, FatPointer{ .archetype = archetypeId, .generation = slimPointer.generation }) catch unreachable;
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }

    // pub fn destroyEntity(entity: Entity) !void {}
};
