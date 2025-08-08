const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const helper = @import("helper.zig");

pub const EntityType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) EntityType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": EntityType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const GenerationType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) GenerationType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": GenerationType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const EntityPointer = struct {
    entity: EntityType,
    generation: GenerationType,
};

pub const ArchetypePointer = struct {
    archetype: ArchetypeType,
    generation: GenerationType,
};

pub fn Arhetypes(comptime T: type) type {
    const @"struct": std.builtin.Type.Struct = helper.getTuple(T);
    var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;

    for (@"struct".fields, 0..) |field, i| {
        new_fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = Archetype(field.type),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Archetype(field.type)),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn Ecs(comptime archetypesTuple: type) type {
    const archetypesInfo = helper.getTuple(archetypesTuple);

    return struct {
        archetypes: Arhetypes(archetypesTuple),
        entityToArchetypeMap: std.AutoArrayHashMapUnmanaged(EntityType, ArchetypePointer),
        unusedEntitys: std.ArrayListUnmanaged(EntityType),
        destoyedEntitys: std.ArrayListUnmanaged(EntityType),
        entityCount: u32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .archetypes = init: {
                    var archetypes: Arhetypes(archetypesTuple) = undefined;
                    inline for (0..archetypes.len) |i| {
                        archetypes[i] = .init;
                    }

                    break :init archetypes;
                },
                .entityToArchetypeMap = .empty,
                .unusedEntitys = .empty,
                .destroyedEntitys = .empty,
                .entityCount = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (0..archetypesInfo.fields.len) |i| {
                self.archetypes[i].deinit(self.allocator);
            }
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn createEntity(self: *Self, comptime T: type, components: T) EntityPointer {
            const newEntity = init: {
                if (self.unusedEntitys.items.len > 0) {
                    break :init self.unusedEntitys.pop().?;
                }

                self.entityCount += 1;
                break :init EntityType.make(self.entityCount - 1);
            };

            inline for (archetypesInfo.fields, 0..) |field, i| {
                if (field.type == T) {
                    self.archetypes[i].append(newEntity, components, self.allocator) catch unreachable;
                    self.entityToArchetypeMap.put(self.allocator, newEntity, ArchetypeType.make(@intCast(i)));

                    return EntityPointer{ .entity = newEntity, .generation = .make(0) };
                }
            }

            @compileError("Supplied type: " ++ @typeName(T) ++ ", didn't have a corresponding archetype");
        }

        pub fn destroyEntity(self: *Self, entity: EntityType) void {
            self.destoyedEntitys.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destoyedEntitys.items) |entity| {
                const archetypePtr = self.entityToArchetypeMap.get(entity).?;
                try self.archetypes[archetypePtr.archetype.value()].remove(entity, self.allocator) catch unreachable;
            }
        }

        pub fn getArchetype(self: *Self, comptime T: type) Archetype(T) {
            inline for (self.archetypes) |archetype| {
                if (T == archetype.components) {
                    return archetype;
                }
            }

            @compileError("Supplied type: " ++ @typeName(T) ++ ", didn't have a corresponding archetype");
        }

        pub fn isArchetypeMatch(comptime components: type, comptime include: type, comptime exclude: type) bool {
            const componentsTuple = helper.getTuple(components);
            const includeTuple = helper.getTuple(include);
            const excludeTuple = helper.getTuple(exclude);

            outer: inline for (includeTuple.fields) |iField| {
                inline for (componentsTuple.fields) |cField| {
                    if (iField.type == cField.type) continue :outer;
                }

                return false;
            }

            inline for (excludeTuple.fields) |iField| {
                inline for (componentsTuple.fields) |cField| {
                    if (iField.type == cField.type) return false;
                }
            }

            return true;
        }

        pub fn getIterator() void {}

        pub fn getTupleIterator() void {}
    };
}
