const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("iterator.zig").TupleIterator;

const compStruct = @import("comptimeStruct.zig");
const TupleOfArrayLists = @import("comptimeStruct.zig").TupleOfArrayLists;
const TupleOfBuffers = @import("comptimeStruct.zig").TupleOfBuffers;

pub const Template: type = struct {
    components: []const type,
    tags: ?[]const type,

    pub fn eql(self: *const Template, other: Template) bool {
        if (self.components.len != other.components.len) return false;

        outer: for (self.components) |component| {
            for (other.components) |component2| {
                if (component == component2) continue :outer;
            }

            return false;
        }

        if (self.tags) |tags| {
            if (other.tags) |tags2| {
                if (tags.len != tags2.len) return false;

                outer: for (tags) |tag| {
                    for (tags2) |tag2| {
                        if (tag == tag2) continue :outer;
                    }

                    return false;
                }
            } else {
                return false;
            }
        } else if (other.tags != null) {
            return false;
        }

        return true;
    }
};

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

// FIXME: generation isn't hadeled correctly currently all new entitys are set to zero even if they existed before.
pub fn Ecs(comptime templates: []const Template) type {
    // FIXME: Remove bad templates maybe?
    for (templates, 1..) |template, i| {
        for (i..templates.len) |j| {
            if (template.eql(templates[j])) @compileError("Two templates where the same which is not allowed. Template one index: " ++ compStruct.itoa(i) ++ ", template two index: " ++ compStruct.itoa(j));
        }
    }

    comptime var componentTypes: []ULandType = &[_]ULandType{};
    comptime var tagsTypes: []ULandType = &[_]ULandType{};

    for (templates, 0..) |template, i| {
        for (template.components, 0..) |component, j| {
            if (@sizeOf(component) == 0) @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ compStruct.itoa(i) ++ ", component index: " ++ compStruct.itoa(j));
            const uLandType = ULandType.get(component);
            for (componentTypes) |existingUlandType| {
                if (uLandType.type == existingUlandType.type) continue;
            }

            componentTypes = @constCast(componentTypes ++ .{uLandType});
        }

        if (template.tags) |tags| {
            for (tags, 0..) |tag, j| {
                if (@sizeOf(tag) != 0) @compileError("Template tag wasn't a ZST, which is not allowed. Template index: " ++ compStruct.itoa(i) ++ ", tag index: " ++ compStruct.itoa(j));
                const uLandType = ULandType.get(tag);
                for (tagsTypes) |existingUlandType| {
                    if (uLandType.type == existingUlandType.type) continue;
                }

                tagsTypes = @constCast(tagsTypes ++ .{uLandType});
            }
        }
    }

    return struct {
        archetypes: init: {
            var newFields: [templates.len]std.builtin.Type.StructField = undefined;

            for (templates, 0..) |template, i| {
                const archetype: type = Archetype(
                    template,
                    componentIds.len,
                    getComponentBitset(template.components),
                    tagIds.len,
                    if (template.tags) |tags| getTagBitset(tags) else TagBitset.initEmpty(),
                );

                newFields[i] = std.builtin.Type.StructField{
                    .name = compStruct.itoa(i),
                    .type = archetype,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(archetype),
                };
            }

            break :init @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &newFields,
                    .decls = &.{},
                    .is_tuple = true,
                },
            });
        },
        entityToArchetypeMap: std.AutoArrayHashMapUnmanaged(EntityType, ArchetypePointer),
        unusedEntitys: std.ArrayListUnmanaged(EntityType),
        destroyedEntitys: std.ArrayListUnmanaged(EntityType),
        entityCount: u32,
        allocator: std.mem.Allocator,

        const Self = @This();
        const componentIds: []ULandType = componentTypes;
        const tagIds: []ULandType = tagsTypes;
        pub const ComponentBitset = std.bit_set.StaticBitSet(componentTypes.len);
        pub const TagBitset = std.bit_set.StaticBitSet(tagsTypes.len);

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .archetypes = init: {
                    var archetypes: @FieldType(Self, "archetypes") = undefined;
                    inline for (0..templates.len) |i| {
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
            inline for (0..templates.len) |i| {
                self.archetypes[i].deinit(self.allocator);
            }

            self.entityToArchetypeMap.deinit(self.allocator);
            self.unusedEntitys.deinit(self.allocator);
            self.destroyedEntitys.deinit(self.allocator);
        }

        pub fn getComponentBitset(comptime components: []const type) ComponentBitset {
            var bitset: ComponentBitset = .initEmpty();
            outer: for (components) |component| {
                const uLandType = ULandType.get(component);
                for (componentIds, 0..) |existingComp, i| {
                    if (uLandType.eql(existingComp)) {
                        bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a component " ++ @typeName(component) ++ ", that wasn't known by the ECS.");
            }

            return bitset;
        }

        pub fn getTagBitset(comptime tags: []const type) TagBitset {
            var bitset: TagBitset = .initEmpty();
            outer: for (tags) |tag| {
                const uLandType = ULandType.get(tag);
                for (tagIds, 0..) |existingComp, i| {
                    if (uLandType.eql(existingComp)) {
                        bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a tag " ++ @typeName(tag) ++ ", that wasn't known by the ECS.");
            }

            return bitset;
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn createEntity(self: *Self, comptime template: Template, components: compStruct.TupleOfComponents(template.components)) EntityPointer {
            const newEntity = init: {
                if (self.unusedEntitys.items.len > 0) {
                    break :init self.unusedEntitys.pop().?;
                }

                self.entityCount += 1;
                break :init EntityType.make(self.entityCount - 1);
            };

            const componentBitset: ComponentBitset = comptime getComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| getTagBitset(tags) else .initEmpty());

            const archetypeIndex: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((archetype.tagBitset.eql(tagBitset) and archetype.componentBitset.eql(componentBitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            if (compStruct.TupleOfComponents(template.components) == compStruct.TupleOfComponents(self.archetypes[archetypeIndex].template.components)) {
                self.archetypes[archetypeIndex].append(newEntity, components, self.allocator) catch unreachable;
                self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(archetypeIndex)), .generation = .make(0) }) catch unreachable;
            } else {
                // NOTE: User was not kind.
                const newComponents: compStruct.TupleOfComponents(self.archetypes[archetypeIndex].template.components) = init: {
                    var newComponents: compStruct.TupleOfComponents(self.archetypes[archetypeIndex].template.components) = undefined;
                    outer: inline for (self.archetypes[archetypeIndex].template.components, 0..) |aComponent, j| {
                        inline for (template.components, 0..) |uComponent, k| {
                            if (aComponent == uComponent) {
                                newComponents[j] = components[k];
                                continue :outer;
                            }
                        }
                    }

                    break :init newComponents;
                };

                self.archetypes[archetypeIndex].append(newEntity, newComponents, self.allocator) catch unreachable;
                self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(archetypeIndex)), .generation = .make(0) }) catch unreachable;
            }

            return EntityPointer{ .entity = newEntity, .generation = .make(0) };
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

        // pub fn getArchetype(self: *Self, comptime template: Template) *Archetype(template) {
        //     inline for (0..self.archetypes.len) |i| {
        //         if (template.components == self.archetypes[i].componentsType and self.archetypes[i].tagsType == template.tags) {
        //             return &self.archetypes[i];
        //         }
        //     }
        //
        //     @compileError("Supplied template, didn't have a corresponding archetype");
        // }
        //
        // pub fn isArchetypeMatch(comptime template: Template, comptime includeTemplate: Template, comptime excludeTemplate: Template) bool {
        //     const componentsTuple = compStruct.getTuple(template.components);
        //     const tagsTuple = compStruct.getTupleAllowEmpty(template.tags);
        //
        //     const iComponentsTuple = compStruct.getTuple(includeTemplate.components);
        //     const iTagsTuple = compStruct.getTupleAllowEmpty(includeTemplate.tags);
        //
        //     const eComponentsTuple = compStruct.getTupleAllowEmpty(excludeTemplate.components);
        //     const etagsTuple = compStruct.getTupleAllowEmpty(excludeTemplate.tags);
        //
        //     outer: inline for (iComponentsTuple.fields) |iField| {
        //         inline for (componentsTuple.fields) |cField| {
        //             if (iField.type == cField.type) continue :outer;
        //         }
        //
        //         return false;
        //     }
        //
        //     outer: inline for (iTagsTuple.fields) |iField| {
        //         inline for (tagsTuple.fields) |cField| {
        //             if (iField.type == cField.type) continue :outer;
        //         }
        //
        //         return false;
        //     }
        //
        //     inline for (eComponentsTuple.fields) |eField| {
        //         inline for (componentsTuple.fields) |cField| {
        //             if (eField.type == cField.type) return false;
        //         }
        //     }
        //
        //     inline for (etagsTuple.fields) |eField| {
        //         inline for (tagsTuple.fields) |cField| {
        //             if (eField.type == cField.type) return false;
        //         }
        //     }
        //
        //     return true;
        // }
        //
        // // fn getInclude(comptime T: type) type {
        // //     var new_fields: [1]std.builtin.Type.StructField = std.builtin.Type.StructField{
        // //         .name = "0",
        // //         .type = []T,
        // //         .default_value_ptr = null,
        // //         .is_comptime = false,
        // //         .alignment = @alignOf([]T),
        // //     };
        // //
        // //     return @Type(.{
        // //         .@"struct" = .{
        // //             .layout = .auto,
        // //             .fields = &new_fields,
        // //             .decls = &.{},
        // //             .is_tuple = true,
        // //         },
        // //     });
        // // }
        //
        // pub fn getIterator(self: *Self, comptime component: type, comptime tags: type, comptime exclude: Template) ?Iterator(component) {
        //     comptime {
        //         // FIXME:: Add a check that there is no crossover with include and exclude
        //         if (@sizeOf(component) == 0) @compileError("Tag was given instead of a component.");
        //         const maxSize = size: {
        //             var size: usize = 0;
        //             for (templates) |template| {
        //                 if (isArchetypeMatch(template, .{ .components = struct { component }, .tags = tags }, exclude)) size += 1;
        //             }
        //
        //             break :size size;
        //         };
        //
        //         if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
        //     }
        //
        //     var componentArrays: std.ArrayListUnmanaged([]component) = .empty;
        //     errdefer componentArrays.deinit(self.allocator);
        //
        //     var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
        //     errdefer entitys.deinit(self.allocator);
        //
        //     inline for (templates, 0..) |template, i| {
        //         if (comptime isArchetypeMatch(template, .{ .components = struct { component }, .tags = tags }, exclude)) {
        //             const array = self.archetypes[i].getComponentArray(component);
        //             if (array.len > 0) {
        //                 componentArrays.append(self.allocator, array) catch unreachable;
        //                 entitys.append(self.allocator, self.archetypes[i].getEntitys()) catch unreachable;
        //             }
        //         }
        //     }
        //
        //     if (componentArrays.items.len == 0) {
        //         return null;
        //     }
        //
        //     return Iterator(component).init(componentArrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        // }
        //
        // pub fn getTupleIterator(self: *Self, comptime template: Template, comptime excludeTemplate: Template) ?TupleIterator(template.components) {
        //     comptime {
        //         // FIXME:: Add a check that there is no crossover with include and exclude
        //         const maxSize = size: {
        //             var size: usize = 0;
        //             for (templates) |temp| {
        //                 if (isArchetypeMatch(temp, template, excludeTemplate)) size += 1;
        //             }
        //
        //             break :size size;
        //         };
        //
        //         if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
        //     }
        //
        //     const components = compStruct.getTuple(template.components);
        //
        //     var tupleOfArrayList: TupleOfArrayLists(template.components) = init: {
        //         var tupleOfArrayList: TupleOfArrayLists(template.components) = undefined;
        //         inline for (0..components.fields.len) |i| {
        //             tupleOfArrayList[i] = .empty;
        //         }
        //
        //         break :init tupleOfArrayList;
        //     };
        //
        //     errdefer {
        //         inline for (0..tupleOfArrayList.len) |i| {
        //             tupleOfArrayList[i].deinit(self.allocator);
        //         }
        //     }
        //
        //     var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
        //     errdefer entitys.deinit(self.allocator);
        //
        //     outer: inline for (templates, 0..) |temp, i| {
        //         if (comptime isArchetypeMatch(temp, template, excludeTemplate)) {
        //             inline for (components.fields, 0..) |component, j| {
        //                 const array = self.archetypes[i].getComponentArray(component.type);
        //                 if (array.len > 0) {
        //                     tupleOfArrayList[j].append(self.allocator, array) catch unreachable;
        //                     if (comptime j == 0) entitys.append(self.allocator, self.archetypes[i].getEntitys()) catch unreachable;
        //                 } else {
        //                     continue :outer;
        //                 }
        //             }
        //         }
        //     }
        //
        //     if (tupleOfArrayList[0].items.len == 0) {
        //         return null;
        //     }
        //
        //     const tupleOfBuffers: TupleOfBuffers(template.components) = init: {
        //         var tupleOfBuffers: TupleOfBuffers(template.components) = undefined;
        //         inline for (0..components.fields.len) |i| {
        //             tupleOfBuffers = tupleOfArrayList[i].toOwnedSlice(self.allocator) catch unreachable;
        //         }
        //
        //         break :init tupleOfBuffers;
        //     };
        //
        //     errdefer {
        //         inline for (tupleOfBuffers) |buffer| {
        //             self.allocator.free(buffer);
        //         }
        //     }
        //
        //     return TupleIterator(template).init(tupleOfBuffers, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        // }
    };
}
