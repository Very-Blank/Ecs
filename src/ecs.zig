const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("tupleIterator.zig").TupleIterator;

const compTypes = @import("comptimeTypes.zig");
const TupleOfSliceArrayLists = @import("comptimeTypes.zig").TupleOfSliceArrayLists;
const TupleOfBuffers = @import("comptimeTypes.zig").TupleOfBuffers;

pub const Template: type = struct {
    components: []const type = &[_]type{},
    tags: ?[]const type = null,

    pub fn hasComponent(self: *const Template, component: type) bool {
        for (self.components) |comp| {
            if (comp == component) return true;
        }

        return false;
    }

    pub fn getComponentIndex(self: *const Template, component: type) usize {
        for (self.components, 0..) |comp, i| {
            if (comp == component) return i;
        }

        @compileError("Invalid component give " ++ @typeName(component) ++ ".");
    }

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

pub const SingletonType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) SingletonType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": SingletonType) u32 {
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

// NOTE: Add functions that assume that entity has a certain template so we can speed up some operations.

pub fn Ecs(comptime templates: []const Template) type {
    // FIXME: Remove bad templates maybe?
    for (templates, 1..) |template, i| {
        for (i..templates.len) |j| {
            if (template.eql(templates[j])) @compileError("Two templates where the same which is not allowed. Template one index: " ++ compTypes.itoa(i) ++ ", template two index: " ++ compTypes.itoa(j));
        }
    }

    return struct {
        archetypes: init: {
            var newFields: [templates.len]std.builtin.Type.StructField = undefined;

            for (templates, 0..) |template, i| {
                const archetype: type = Archetype(
                    template,
                    componentTypes.len,
                    comptimeGetComponentBitset(template.components),
                    tagsTypes.len,
                    if (template.tags) |tags| comptimeGetTagBitset(tags) else TagBitset.initEmpty(),
                );

                newFields[i] = std.builtin.Type.StructField{
                    .name = compTypes.itoa(i),
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

        singletons: std.ArrayListUnmanaged(struct { ComponentBitset, TagBitset }),
        singletonToEntityMap: std.AutoHashMapUnmanaged(SingletonType, EntityPointer),

        entityCount: u32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub const componentTypes: []ULandType = init: {
            var iComponentTypes: []ULandType = &[_]ULandType{};
            for (templates, 0..) |template, i| {
                if (templates.len == 0) @compileError("Template components was empty, which is not allowed. Template index: " ++ compTypes.itoa(i) ++ ".");
                outer: for (template.components, 0..) |component, j| {
                    if (@sizeOf(component) == 0) @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ compTypes.itoa(i) ++ ", component index: " ++ compTypes.itoa(j));
                    const uLandType = ULandType.get(component);
                    for (iComponentTypes) |existingUlandType| {
                        if (uLandType.type == existingUlandType.type) continue :outer;
                    }

                    iComponentTypes = @constCast(iComponentTypes ++ .{uLandType});
                }
            }

            break :init iComponentTypes;
        };

        pub const tagsTypes: []ULandType = init: {
            var iTagsTypes: []ULandType = &[_]ULandType{};
            for (templates, 0..) |template, i| {
                if (template.tags) |tags| {
                    if (tags.len == 0) @compileError("Template tags was empty, which is not allowed; rather use null. Template index: " ++ compTypes.itoa(i) ++ ".");
                    outer: for (tags, 0..) |tag, j| {
                        if (@sizeOf(tag) != 0) @compileError("Template tag wasn't a ZST, which is not allowed. Template index: " ++ compTypes.itoa(i) ++ ", tag index: " ++ compTypes.itoa(j));
                        const uLandType = ULandType.get(tag);
                        for (iTagsTypes) |existingUlandType| {
                            if (uLandType.type == existingUlandType.type) continue :outer;
                        }

                        iTagsTypes = @constCast(iTagsTypes ++ .{uLandType});
                    }
                }
            }

            break :init iTagsTypes;
        };

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
                .singletons = .empty,
                .singletonToEntityMap = .empty,
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

            self.singletons.deinit(self.allocator);
            self.singletonToEntityMap.deinit(self.allocator);
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn getEntityPointer(self: *Self, entity: EntityType) !EntityPointer {
            if (self.entityToArchetypeMap.get(entity)) |archetypePtr| {
                return .{ .entity = entity, .generation = archetypePtr.generation };
            }

            return error.MissingEntity;
        }

        pub fn createEntity(self: *Self, comptime template: Template, components: compTypes.TupleOfItems(template.components)) EntityPointer {
            const newEntity: EntityType, const generation: GenerationType = init: {
                if (self.unusedEntitys.items.len > 0) {
                    const entityPtr = self.unusedEntitys.pop().?;
                    break :init .{ entityPtr.entity, GenerationType.make(entityPtr.generation.value() + 1) };
                }

                self.entityCount += 1;
                break :init .{ EntityType.make(self.entityCount - 1), GenerationType.make(0) };
            };

            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const archetypeIndex: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((@TypeOf(archetype).tagBitset.eql(tagBitset) and @TypeOf(archetype).componentBitset.eql(componentBitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            if (compTypes.TupleOfItems(template.components) == compTypes.TupleOfItems(self.archetypes[archetypeIndex].template.components)) {
                self.archetypes[archetypeIndex].append(newEntity, components, self.allocator) catch unreachable;
                self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(archetypeIndex)), .generation = generation }) catch unreachable;
            } else {
                // NOTE: User was not kind.
                const newComponents: compTypes.TupleOfItems(self.archetypes[archetypeIndex].template.components) = init: {
                    var newComponents: compTypes.TupleOfItems(self.archetypes[archetypeIndex].template.components) = undefined;
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

            self.destroyedEntitys.clearAndFree(self.allocator);
        }

        pub fn entityHasComponent(
            self: *Self,
            entity: EntityType,
            comptime component: type,
        ) bool {
            const archetypeIndex: u32 = self.entityToArchetypeMap.get(entity).?.archetype.value();
            inline for (self.archetypes, 0..) |archetype, i| {
                if (i == archetypeIndex) {
                    if (comptime archetype.template.hasComponent(component)) {
                        return true;
                    }
                    return false;
                }
            }

            return false;
        }

        pub fn getEntityComponent(
            self: *Self,
            entity: EntityType,
            comptime component: type,
        ) !*component {
            const archetypeIndex: u32 = self.entityToArchetypeMap.get(entity).?.archetype.value();
            inline for (self.archetypes, 0..) |archetype, i| {
                if (i == archetypeIndex) {
                    if (comptime archetype.template.hasComponent(component)) {
                        const columnIndex = comptime archetype.template.getComponentIndex(component);
                        return &archetype.tupleArrayList.tupleOfManyPointers[columnIndex][archetype.entityToRowMap.get(entity).?.value()];
                    }
                    return error.ComponentNotFound;
                }
            }

            return error.ComponentNotFound;
        }

        /// This will transfer entity from one archetype to another, but this will require an existing component.
        pub fn addComponentToEntity(self: Self, entity: EntityType, comptime T: type, component: T) !void {
            const oldArchetypeIndex: u32 = self.entityToArchetypeMap.get(entity).?.archetype.value();
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(&.{T});

            inline for (0..self.archetypes.len) |i| {
                if (i == oldArchetypeIndex) {
                    const newComponentBitset = comptime self.archetypes[i].componentBitset.unionWith(componentBitset);
                    const newArchtypeIndex = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).componentBitset.intersectWith(newComponentBitset).eql(newComponentBitset) and
                                @TypeOf(self.archetypes[j]).tagBitset.intersectWith(self.archetypes[i].tagBitset).eql(self.archetypes[i].tagBitset))
                            {
                                break :init j;
                            }
                        }
                    };

                    self.archetypes[newArchtypeIndex].append(entity, self.archetypes[i].popRemove(entity) catch unreachable, self.allocator);
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        pub fn removeComponentToEntity(self: Self, entity: EntityType, comptime component: type) !void {
            const oldArchetypeIndex: u32 = self.entityToArchetypeMap.get(entity).?.archetype.value();
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(&.{component});

            inline for (0..self.archetypes.len) |i| {
                if (i == oldArchetypeIndex) {
                    const newComponentBitset = comptime self.archetypes[i].componentBitset.unionWith(componentBitset);
                    const newArchtypeIndex = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).componentBitset.intersectWith(newComponentBitset).eql(newComponentBitset) and
                                @TypeOf(self.archetypes[j]).tagBitset.intersectWith(self.archetypes[i].tagBitset).eql(self.archetypes[i].tagBitset))
                            {
                                break :init j;
                            }
                        }
                    };



                    self.archetypes[newArchtypeIndex].append(entity,  catch unreachable, self.allocator);
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        // pub fn addTagToEntity(self: Self, entity: EntityType, comptime tag: type) !void {}
        //
        // pub fn removeTagToEntity(self: Self, entity: EntityType, comptime tag: type) !void {}

        pub fn comptimeGetComponentBitset(comptime components: []const type) ComponentBitset {
            var bitset: ComponentBitset = .initEmpty();
            outer: for (components) |component| {
                const uLandType = ULandType.get(component);
                for (componentTypes, 0..) |existingComp, i| {
                    if (uLandType.eql(existingComp)) {
                        if (bitset.isSet(i)) {
                            @compileError("Components had two of the same component " ++ @typeName(component) ++ ", Which is not allowed.");
                        }

                        bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a component " ++ @typeName(component) ++ ", that wasn't known by the ECS.");
            }

            return bitset;
        }

        pub fn comptimeGetTagBitset(comptime tags: []const type) TagBitset {
            var bitset: TagBitset = .initEmpty();
            outer: for (tags) |tag| {
                const uLandType = ULandType.get(tag);
                for (tagsTypes, 0..) |existingComp, i| {
                    if (uLandType.eql(existingComp)) {
                        if (bitset.isSet(i)) {
                            @compileError("Tags had two of the same tag " ++ @typeName(tag) ++ ", Which is not allowed.");
                        }

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
                comptimeGetComponentBitset(mTemplate.components),
                tagsTypes.len,
                if (mTemplate.tags) |tags| comptimeGetTagBitset(tags) else TagBitset.initEmpty(),
            );
        } {
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const archetypeIndex: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((@TypeOf(archetype).tagBitset.eql(tagBitset) and @TypeOf(archetype).componentBitset.eql(componentBitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            return &self.archetypes[archetypeIndex];
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getIterator(self: *Self, comptime component: type, comptime @"tags?": ?[]const type, comptime exclude: Template) ?Iterator(component) {
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(&[_]type{component});
            const tagBitset: TagBitset = comptime (if (@"tags?") |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const excludeComponentBitset: ComponentBitset = comptime comptimeGetComponentBitset(exclude.components);
            const excludeTagBitset: TagBitset = comptime (if (exclude.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const matchinArchetypesIndices: []const usize = comptime init: {
                var matchinArchetypesIndices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (@TypeOf(archetype).componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                        @TypeOf(archetype).tagBitset.intersectWith(tagBitset).eql(tagBitset) and
                        @TypeOf(archetype).componentBitset.intersectWith(excludeComponentBitset).eql(ComponentBitset.initEmpty()) and
                        @TypeOf(archetype).tagBitset.intersectWith(excludeTagBitset).eql(TagBitset.initEmpty()))
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
                if (self.archetypes[index].tupleArrayList.count > 0) {
                    const array = self.archetypes[index].tupleArrayList.getItemArray(component);
                    componentArrays.append(self.allocator, array) catch unreachable;
                    entitys.append(self.allocator, self.archetypes[index].entitys.items) catch unreachable;
                }
            }

            if (componentArrays.items.len == 0) {
                return null;
            }

            return Iterator(component).init(componentArrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getTupleIterator(self: *Self, comptime template: Template, comptime exclude: Template) ?TupleIterator(template.components) {
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tagBitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const excludeComponentBitset: ComponentBitset = comptime comptimeGetComponentBitset(exclude.components);
            const excludeTagBitset: TagBitset = comptime (if (exclude.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const matchinArchetypesIndices: []const usize = comptime init: {
                var matchinArchetypesIndices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (@TypeOf(archetype).componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                        @TypeOf(archetype).tagBitset.intersectWith(tagBitset).eql(tagBitset) and
                        @TypeOf(archetype).componentBitset.intersectWith(excludeComponentBitset).eql(ComponentBitset.initEmpty()) and
                        @TypeOf(archetype).tagBitset.intersectWith(excludeTagBitset).eql(TagBitset.initEmpty()))
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
                inline for (template.components, 0..) |component, j| {
                    if (self.archetypes[index].tupleArrayList.count > 0) {
                        const array = self.archetypes[index].tupleArrayList.getItemArray(component);
                        tupleOfArrayList[j].append(self.allocator, array) catch unreachable;
                        if (comptime j == 0) entitys.append(self.allocator, self.archetypes[index].entitys.items) catch unreachable;
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

        pub fn createSingleton(self: *Self, requirements: Template) SingletonType {
            const componentBitset: ComponentBitset = comptime comptimeGetComponentBitset(requirements.components);
            const tagBitset: TagBitset = comptime (if (requirements.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());
            comptime check: {
                for (self.archetypes) |archetype| {
                    if (@TypeOf(archetype).componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                        @TypeOf(archetype).tagBitset.intersectWith(tagBitset).eql(tagBitset))
                    {
                        break :check;
                    }
                }

                @compileError("No matching archetype");
            }

            self.singletons.append(self.allocator, .{ componentBitset, tagBitset }) catch unreachable;
            return SingletonType.make(@intCast(self.singletons.items.len - 1));
        }

        pub fn setSingletonsEntity(self: *Self, singleton: SingletonType, entityPtr: EntityPointer) !void {
            std.debug.assert(singleton.value() < self.singletons.items.len);
            const componentBitset, const tagBitset = self.singletons.items[singleton.value()];

            inline for (self.archetypes) |archetype| {
                if (@TypeOf(archetype).componentBitset.intersectWith(componentBitset).eql(componentBitset) and
                    @TypeOf(archetype).tagBitset.intersectWith(tagBitset).eql(tagBitset))
                {
                    if (archetype.entityToRowMap.get(entityPtr.entity) != null) {
                        self.singletonToEntityMap.put(self.allocator, singleton, entityPtr) catch unreachable;
                        return;
                    }
                }
            }

            return error.EntityNotMatchRequirments;
        }

        pub fn getSingletonsEntity(self: *Self, singleton: SingletonType) ?EntityPointer {
            std.debug.assert(singleton.value() < self.singletons.items.len);
            if (self.singletonToEntityMap.get(singleton)) |entity| {
                if (self.entityToArchetypeMap.get(entity.entity)) |_| {
                    return entity;
                }

                std.debug.assert(self.singletonToEntityMap.remove(singleton));
            }

            return null;
        }
    };
}

test "Getting a bitset" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);
    defer ecs.deinit();

    const EcsType: type = @TypeOf(ecs);

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(0);
        const componentBitset = comptime EcsType.comptimeGetComponentBitset(&[_]type{Position});
        try std.testing.expect(expected.eql(componentBitset));
    }

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(0);
        expected.set(1);
        const componentBitset = comptime EcsType.comptimeGetComponentBitset(&[_]type{ Position, Collider });
        try std.testing.expect(expected.eql(componentBitset));
    }

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(1);
        const componentBitset = comptime EcsType.comptimeGetComponentBitset(&[_]type{Collider});
        try std.testing.expect(expected.eql(componentBitset));
    }

    {
        var expected = EcsType.TagBitset.initEmpty();
        expected.set(0);
        const tagBitset = comptime EcsType.comptimeGetTagBitset(&[_]type{Tag});
        try std.testing.expect(expected.eql(tagBitset));
    }
}

test "Creating a new entity" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Collider, Position }, .tags = &[_]type{Tag} },
            .{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    const archetype = ecs.getArchetype(.{ .components = &[_]type{ Collider, Position }, .tags = &[_]type{Tag} });

    try std.testing.expect(archetype.tupleArrayList.count == 100);

    const positions = archetype.tupleArrayList.getItemArray(Position);

    for (positions) |item| {
        try std.testing.expect(item.x == 4);
        try std.testing.expect(item.y == 4);
    }

    const colliders = archetype.tupleArrayList.getItemArray(Collider);
    for (colliders) |item| {
        try std.testing.expect(item.x == 5);
        try std.testing.expect(item.y == 5);
    }
}

test "Getting a single component that an entity owns." {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &[_]type{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            position.x = 2;
        }

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 2, .y = 1 }, position.*);
        }
    }

    _ = ecs.createEntity(
        .{ .components = &[_]type{ Collider, Position }, .tags = &[_]type{Tag} },
        .{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } },
    );
}

test "Destroing an entity" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    const entityPtr = ecs.createEntity(
        .{ .components = &[_]type{Position} },
        .{Position{ .x = 1, .y = 1 }},
    );

    try std.testing.expect(ecs.entityIsValid(entityPtr) == true);

    ecs.destroyEntity(entityPtr.entity);

    ecs.clearDestroyedEntitys();
    try std.testing.expect(ecs.destroyedEntitys.items.len == 0);
    try std.testing.expect(ecs.unusedEntitys.items.len == 1);

    try std.testing.expect(ecs.entityIsValid(entityPtr) == false);

    const entityPtr2 = ecs.createEntity(
        .{ .components = &[_]type{Position} },
        .{Position{ .x = 1, .y = 1 }},
    );

    try std.testing.expect(ecs.entityIsValid(entityPtr2) == true);

    try std.testing.expect(entityPtr.entity.value() == entityPtr2.entity.value());
    try std.testing.expect(entityPtr.generation.value() == entityPtr2.generation.value() - 1);
}

test "Iterating over a component" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{} }).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.buffers.len == 3);
    try std.testing.expect(iterator.buffers[0].len == 100);
    try std.testing.expect(iterator.buffers[1].len == 100);
    try std.testing.expect(iterator.buffers[2].len == 100);

    while (iterator.next()) |position| {
        try std.testing.expect(position.x == 1);
        try std.testing.expect(position.y == 1);
        position.x = 5;
        position.y = 2;
    }

    iterator.reset();

    while (iterator.next()) |position| {
        try std.testing.expect(position.x == 5);
        try std.testing.expect(position.y == 2);
    }

    var iterator2: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{}, .tags = &[_]type{Tag} }).?;
    defer iterator2.deinit();

    try std.testing.expect(iterator2.buffers.len == 1);
    try std.testing.expect(iterator2.buffers[0].len == 100);

    while (iterator2.next()) |position| {
        try std.testing.expect(position.x == 5);
        try std.testing.expect(position.y == 2);
    }
}

test "Checking iterator entitys" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
        );
    }

    {
        var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{} }).?;
        defer iterator.deinit();

        var i: u32 = 0;
        while (iterator.next()) |_| {
            try std.testing.expect(iterator.getCurrentEntity().value() == i);
            i += 1;
        }
    }

    {
        ecs.destroyEntity(EntityType.make(0));
        ecs.clearDestroyedEntitys();

        var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{ .components = &[_]type{} }).?;
        defer iterator.deinit();
        if (iterator.next()) |_| {
            try std.testing.expect(iterator.currentEntity.value() == 99);
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "Iterating over multiple components" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
            .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: TupleIterator(&[_]type{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &[_]type{ Position, Collider } },
        .{ .components = &[_]type{} },
    ).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.tupleOfBuffers[0].len == 1);
    try std.testing.expect(iterator.tupleOfBuffers[0][0].len == 100);

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 6);
        try std.testing.expect(components[0].y == 5);
        components[0].x = 7;
        components[0].y = 7;
    }

    var iterator2: TupleIterator(&[_]type{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &[_]type{ Position, Collider } },
        .{},
    ).?;
    defer iterator2.deinit();

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 7);
        try std.testing.expect(components[0].y == 7);
    }
}

test "Singletons" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    var ecs: Ecs(&[_]Template{
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ .components = &[_]type{Position} },
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    const entity1 = ecs.createEntity(
        .{ .components = &[_]type{ Position, Collider }, .tags = &[_]type{Tag} },
        .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
    );
    const entity2 = ecs.createEntity(
        .{ .components = &[_]type{Position} },
        .{Position{ .x = 1, .y = 1 }},
    );
    const entity3 = ecs.createEntity(
        .{ .components = &[_]type{Position}, .tags = &[_]type{Tag} },
        .{Position{ .x = 1, .y = 1 }},
    );

    {
        const singleton = ecs.createSingleton(.{ .components = &[_]type{Position}, .tags = &[_]type{Tag} });
        try std.testing.expect(ecs.getSingletonsEntity(singleton) == null);

        ecs.setSingletonsEntity(singleton, entity1) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        testScope: {
            ecs.setSingletonsEntity(singleton, entity2) catch {
                break :testScope;
            };

            return error.TestUnexpectedResult;
        }

        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        ecs.setSingletonsEntity(singleton, entity3) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity3.entity);
    }

    {
        const singleton = ecs.createSingleton(.{ .components = &[_]type{Position} });
        try std.testing.expect(ecs.getSingletonsEntity(singleton) == null);

        ecs.setSingletonsEntity(singleton, entity1) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        ecs.setSingletonsEntity(singleton, entity2) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity2.entity);

        ecs.setSingletonsEntity(singleton, entity3) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity3.entity);
    }
}
