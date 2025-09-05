const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("tupleIterator.zig").TupleIterator;

const compStruct = @import("comptimeStruct.zig");
const TupleOfSliceArrayLists = @import("comptimeStruct.zig").TupleOfSliceArrayLists;
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
        if (templates.len == 0) @compileError("Template components was empty, which is not allowed. Template index: " ++ compStruct.itoa(i) ++ ".");
        outer: for (template.components, 0..) |component, j| {
            if (@sizeOf(component) == 0) @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ compStruct.itoa(i) ++ ", component index: " ++ compStruct.itoa(j));
            const uLandType = ULandType.get(component);
            for (componentTypes) |existingUlandType| {
                if (uLandType.type == existingUlandType.type) continue :outer;
            }

            componentTypes = @constCast(componentTypes ++ .{uLandType});
        }

        if (template.tags) |tags| {
            if (tags.len == 0) @compileError("Template tags was empty, which is not allowed; rather use null. Template index: " ++ compStruct.itoa(i) ++ ".");
            outer: for (tags, 0..) |tag, j| {
                if (@sizeOf(tag) != 0) @compileError("Template tag wasn't a ZST, which is not allowed. Template index: " ++ compStruct.itoa(i) ++ ", tag index: " ++ compStruct.itoa(j));
                const uLandType = ULandType.get(tag);
                for (tagsTypes) |existingUlandType| {
                    if (uLandType.type == existingUlandType.type) continue :outer;
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
                    componentTypes.len,
                    getComponentBitset(template.components),
                    tagsTypes.len,
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
        entityToArchetypeMap: std.AutoHashMapUnmanaged(EntityType, ArchetypePointer),
        unusedEntitys: std.ArrayListUnmanaged(EntityPointer),
        destroyedEntitys: std.ArrayListUnmanaged(EntityType),
        componentIds: []ULandType,
        tagIds: []ULandType,
        entityCount: u32,
        allocator: std.mem.Allocator,

        const Self = @This();
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
                .componentIds = componentTypes,
                .tagIds = tagsTypes,
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

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn createEntity(self: *Self, comptime template: Template, components: compStruct.TupleOfComponents(template.components)) EntityPointer {
            const newEntity: EntityType, const generation: GenerationType = init: {
                if (self.unusedEntitys.items.len > 0) {
                    const entityPtr = self.unusedEntitys.pop().?;
                    break :init .{ entityPtr.entity, GenerationType.make(entityPtr.generation.value() + 1) };
                }

                self.entityCount += 1;
                break :init .{ EntityType.make(self.entityCount - 1), GenerationType.make(0) };
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
                self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(archetypeIndex)), .generation = generation }) catch unreachable;
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
                self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(archetypeIndex)), .generation = generation }) catch unreachable;
            }

            return EntityPointer{ .entity = newEntity, .generation = generation };
        }

        pub fn destroyEntity(self: *Self, entity: EntityType) void {
            self.destroyedEntitys.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destroyedEntitys.items) |entity| {
                const archetypePtr = self.entityToArchetypeMap.get(entity).?;
                inline for (0..self.archetypes.len) |i| {
                    if (i == archetypePtr.archetype.value()) {
                        self.archetypes[i].remove(entity, self.allocator) catch unreachable;
                    }
                }

                std.debug.assert(self.entityToArchetypeMap.remove(entity));

                self.unusedEntitys.append(self.allocator, EntityPointer{ .entity = entity, .generation = archetypePtr.generation }) catch unreachable;
            }
        }

        pub fn getComponentBitset(comptime components: []const type) ComponentBitset {
            var bitset: ComponentBitset = .initEmpty();
            outer: for (components) |component| {
                const uLandType = ULandType.get(component);
                for (componentTypes, 0..) |existingComp, i| {
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
                for (tagsTypes, 0..) |existingComp, i| {
                    if (uLandType.eql(existingComp)) {
                        bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a tag " ++ @typeName(tag) ++ ", that wasn't known by the ECS.");
            }

            return bitset;
        }

        fn getMeantArchetypeTemplate(template: Template) Template {
            for (templates) |temp| {
                if (temp.eql(template)) return temp;
            }

            @compileError("Supplied template didn't have a corresponding archetype.");
        }

        pub fn getArchetype(self: *Self, comptime template: Template) init: {
            const mTemplate = getMeantArchetypeTemplate(template);
            break :init *Archetype(
                mTemplate,
                componentTypes.len,
                getComponentBitset(mTemplate.components),
                tagsTypes.len,
                if (mTemplate.tags) |tags| getTagBitset(tags) else TagBitset.initEmpty(),
            );
        } {
            const componentBitset: ComponentBitset = comptime getComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| getTagBitset(tags) else .initEmpty());

            const archetypeIndex: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((archetype.tagBitset.eql(tagBitset) and archetype.componentBitset.eql(componentBitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            return &self.archetypes[archetypeIndex];
        }

        pub fn getIterator(self: *Self, comptime component: type, comptime @"tags?": ?[]const type, comptime exclude: Template) ?Iterator(component) {
            const componentBitset: ComponentBitset = comptime getComponentBitset(&[_]type{component});
            const tagBitset: TagBitset = comptime (if (@"tags?") |tags| getTagBitset(tags) else .initEmpty());

            const excludeComponentBitset: ComponentBitset = comptime getComponentBitset(exclude.components);
            const excludeTagBitset: TagBitset = comptime (if (exclude.tags) |tags| getTagBitset(tags) else .initEmpty());

            const matchinArchetypesIndices: []const usize = comptime init: {
                var matchinArchetypesIndices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (archetype.componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                        archetype.tagBitset.intersectWith(tagBitset).eql(tagBitset) and
                        archetype.componentBitset.intersectWith(excludeComponentBitset).eql(ComponentBitset.initEmpty()) and
                        archetype.tagBitset.intersectWith(excludeTagBitset).eql(TagBitset.initEmpty()))
                    {
                        matchinArchetypesIndices = @constCast(matchinArchetypesIndices ++ .{i});
                    }
                }
                if (matchinArchetypesIndices.len == 0) @compileError("No matching archetypes with the supplied include and exclude.");
                break :init matchinArchetypesIndices;
            };

            var componentArrays: std.ArrayListUnmanaged([]component) = .empty;
            errdefer componentArrays.deinit(self.allocator);

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            inline for (matchinArchetypesIndices) |index| {
                const array = self.archetypes[index].getComponentArray(component);
                if (array.len > 0) {
                    componentArrays.append(self.allocator, array) catch unreachable;
                    entitys.append(self.allocator, self.archetypes[index].getEntitys()) catch unreachable;
                }
            }

            if (componentArrays.items.len == 0) {
                return null;
            }

            return Iterator(component).init(componentArrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        pub fn getTupleIterator(self: *Self, comptime template: Template, comptime exclude: Template) ?TupleIterator(template.components) {
            const componentBitset: ComponentBitset = comptime getComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| getTagBitset(tags) else .initEmpty());

            const excludeComponentBitset: ComponentBitset = comptime getComponentBitset(exclude.components);
            const excludeTagBitset: TagBitset = comptime (if (exclude.tags) |tags| getTagBitset(tags) else .initEmpty());

            const matchinArchetypesIndices: []const usize = comptime init: {
                var matchinArchetypesIndices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (archetype.componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                        archetype.tagBitset.intersectWith(tagBitset).eql(tagBitset) and
                        archetype.componentBitset.intersectWith(excludeComponentBitset).eql(ComponentBitset.initEmpty()) and
                        archetype.tagBitset.intersectWith(excludeTagBitset).eql(TagBitset.initEmpty()))
                    {
                        matchinArchetypesIndices = @constCast(matchinArchetypesIndices ++ .{i});
                    }
                }
                if (matchinArchetypesIndices.len == 0) @compileError("No matching archetypes with the supplied include and exclude.");
                break :init matchinArchetypesIndices;
            };

            var tupleOfArrayList: TupleOfSliceArrayLists(template.components) = init: {
                var tupleOfArrayList: TupleOfSliceArrayLists(template.components) = undefined;
                inline for (0..template.components.len) |i| {
                    tupleOfArrayList[i] = .empty;
                }

                break :init tupleOfArrayList;
            };

            errdefer {
                inline for (0..tupleOfArrayList.len) |i| {
                    tupleOfArrayList[i].deinit(self.allocator);
                }
            }

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            inline for (matchinArchetypesIndices) |index| {
                inline for (self.archetypes[index].template.components, 0..) |component, j| {
                    const array = self.archetypes[index].getComponentArray(component);
                    if (array.len > 0) {
                        tupleOfArrayList[j].append(self.allocator, array) catch unreachable;
                        if (comptime j == 0) entitys.append(self.allocator, self.archetypes[index].getEntitys()) catch unreachable;
                    }
                }
            }

            if (tupleOfArrayList[0].items.len == 0) {
                return null;
            }

            const tupleOfBuffers: TupleOfBuffers(template.components) = init: {
                var tupleOfBuffers: TupleOfBuffers(template.components) = undefined;
                inline for (0..template.components.len) |i| {
                    tupleOfBuffers[i] = tupleOfArrayList[i].toOwnedSlice(self.allocator) catch unreachable;
                }

                break :init tupleOfBuffers;
            };

            errdefer {
                inline for (tupleOfBuffers) |buffer| {
                    self.allocator.free(buffer);
                }
            }

            return TupleIterator(template.components).init(tupleOfBuffers, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }
    };
}
