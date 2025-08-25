const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;

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

// FIXME: generation isn't hadeled correctly currently all new entitys are set to zero even if they existed before.

pub fn Ecs(comptime archetypesTuple: type) type {
    const archetypesInfo = helper.getTuple(archetypesTuple);

    return struct {
        archetypes: Arhetypes(archetypesTuple),
        entityToArchetypeMap: std.AutoArrayHashMapUnmanaged(EntityType, ArchetypePointer),
        unusedEntitys: std.ArrayListUnmanaged(EntityType),
        destroyedEntitys: std.ArrayListUnmanaged(EntityType),
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

            self.entityToArchetypeMap.deinit(self.allocator);
            self.unusedEntitys.deinit(self.allocator);
            self.destroyedEntitys.deinit(self.allocator);
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        // pub fn createEntity(self: *Self, comptime data: struct { comps: type, flags: type }, components: data.comps) EntityPointer {
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
                    self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(i)), .generation = .make(0) }) catch unreachable;

                    return EntityPointer{ .entity = newEntity, .generation = .make(0) };
                }
            }

            @compileError("Supplied type: " ++ @typeName(T) ++ ", didn't have a corresponding archetype");
        }

        pub fn destroyEntity(self: *Self, entity: EntityType) void {
            self.destroyedEntitys.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destroyedEntitys.items) |entity| {
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

            @compileError("Supplied type didn't have a corresponding archetype.");
        }

        pub fn isArchetypeMatch(comptime components: type, comptime include: type, comptime tags: type, comptime exclude: type) bool {
            const componentsTuple = helper.getTuple(components);
            helper.compileErrorIfZSTInStruct(include);
            const includeTuple = helper.getTuple(include);
            const tagsTuple = helper.getTupleAllowEmpty(tags);
            const excludeTuple = helper.getTupleAllowEmpty(exclude);

            outer: inline for (includeTuple.fields) |iField| {
                inline for (componentsTuple.fields) |cField| {
                    if (iField.type == cField.type) continue :outer;
                }

                return false;
            }

            outer: inline for (tagsTuple.fields) |iField| {
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

        // fn getInclude(comptime T: type) type {
        //     var new_fields: [1]std.builtin.Type.StructField = std.builtin.Type.StructField{
        //         .name = "0",
        //         .type = []T,
        //         .default_value_ptr = null,
        //         .is_comptime = false,
        //         .alignment = @alignOf([]T),
        //     };
        //
        //     return @Type(.{
        //         .@"struct" = .{
        //             .layout = .auto,
        //             .fields = &new_fields,
        //             .decls = &.{},
        //             .is_tuple = true,
        //         },
        //     });
        // }

        pub fn getIterator(self: *Self, comptime component: type, comptime tags: type, comptime exclude: type) ?Iterator(component) {
            comptime {
                if (@sizeOf(component) == 0) @compileError("Can't iterate over componets that are zero sized.");
                const maxSize = size: {
                    var size: usize = 0;
                    for (archetypesInfo.fields) |field| {
                        if (isArchetypeMatch(field.type, struct { component }, exclude)) size += 1;
                    }

                    break :size size;
                };

                if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
            }

            var componentArrays: std.ArrayListUnmanaged([]component) = .empty;
            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer componentArrays.deinit(self.allocator);
            errdefer entitys.deinit(self.allocator);

            inline for (archetypesInfo.fields, 0..) |field, j| {
                if (comptime isArchetypeMatch(field.type, struct { component } ++ tags, exclude)) {
                    const array = self.archetypes[j].getComponentArray(component);
                    if (array.len > 0) {
                        componentArrays.append(self.allocator, array) catch unreachable;
                        entitys.append(self.allocator, self.archetypes[j].getEntitys()) catch unreachable;
                    }
                }
            }

            if (componentArrays.items.len == 0) {
                return null;
            }

            return Iterator(component).init(componentArrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        // pub fn getTupleIterator(self: *Self, comptime include: type, comptime exclude: type) void {
        //     comptime {
        //         const maxSize = size: {
        //             var size: usize = 0;
        //             for (archetypesInfo.fields) |field| {
        //                 if (isArchetypeMatch(field.type, include, exclude)) size += 1;
        //             }
        //
        //             break :size size;
        //         };
        //
        //         if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
        //     }
        //
        //     comptime const noZST = helper.removeZST(include);
        // }
    };
}
