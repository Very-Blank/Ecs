const std = @import("std");
const ct = @import("comptimeTypes.zig");

const ULandType = @import("uLandType.zig").ULandType;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("tupleIterator.zig").TupleIterator;

const TupleOfSliceArrayLists = @import("comptimeTypes.zig").TupleOfSliceArrayLists;
const TupleOfBuffers = @import("comptimeTypes.zig").TupleOfBuffers;

pub const Template: type = struct {
    components: []const type = &.{},
    tags: ?[]const type = null,

    pub fn hasComponent(self: *const Template, component: type) bool {
        for (self.components) |comp| {
            if (comp == component) return true;
        }

        return false;
    }

    pub fn hasTag(self: *const Template, tag: type) bool {
        if (self.tags) |tags| {
            for (tags) |t| {
                if (t == tag) return true;
            }
        }

        return false;
    }

    pub fn getComponentIndex(self: *const Template, component: type) usize {
        for (self.components, 0..) |comp, i| {
            if (comp == component) return i;
        }

        @compileError("Invalid component given, " ++ @typeName(component) ++ ". Wasn't in the components list.");
    }

    pub fn getTagIndex(self: *const Template, tag: type) usize {
        if (self.tags) |tags| {
            for (tags, 0..) |t, i| {
                if (t == tag) return i;
            }
        } else {
            @compileError("Invalid tag given, " ++ @typeName(tag) ++ ". Template didn't have tags.");
        }

        @compileError("Invalid tag given, " ++ @typeName(tag) ++ ". Wasn't in the tag list");
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
    if (templates.len == 0) {
        @compileError("Was called with an empty template array.");
    }

    // FIXME: Remove bad templates maybe?
    for (templates, 1..) |template, i| {
        for (i..templates.len) |j| {
            if (template.eql(templates[j])) @compileError("Two templates where the same which is not allowed. Template one index: " ++ ct.itoa(i) ++ ", template two index: " ++ ct.itoa(j));
        }
    }

    return struct {
        archetypes: init: {
            var newFields: [templates.len]std.builtin.Type.StructField = undefined;

            for (templates, 0..) |template, i| {
                const archetype: type = Archetype(
                    template,
                    component_types.len,
                    comptimeGetComponentBitset(template.components),
                    tags_types.len,
                    if (template.tags) |tags| comptimeGetTagBitset(tags) else TagBitset.initEmpty(),
                );

                newFields[i] = std.builtin.Type.StructField{
                    .name = ct.itoa(i),
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
        entity_to_archetype_map: std.AutoHashMapUnmanaged(EntityType, ArchetypePointer),
        unused_entitys: std.ArrayListUnmanaged(EntityPointer),
        destroyed_entitys: std.ArrayListUnmanaged(EntityType),

        singletons: std.ArrayListUnmanaged(struct { ComponentBitset, TagBitset }),
        singleton_to_entity_map: std.AutoHashMapUnmanaged(SingletonType, EntityPointer),

        entity_count: u32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub const component_types: []const ULandType = init: {
            var i_component_types: []ULandType = &[_]ULandType{};
            for (templates, 0..) |template, i| {
                if (template.components.len == 0) @compileError("Template components was empty, which is not allowed. Template index: " ++ ct.itoa(i) ++ ".");
                outer: for (template.components, 0..) |component, j| {
                    if (@sizeOf(component) == 0) @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ ct.itoa(i) ++ ", component index: " ++ ct.itoa(j));
                    const uLandType = ULandType.get(component);
                    for (i_component_types) |existing_ULandType| {
                        if (uLandType.type == existing_ULandType.type) continue :outer;
                    }

                    i_component_types = @constCast(i_component_types ++ .{uLandType});
                }
            }

            break :init i_component_types;
        };

        pub const tags_types: []const ULandType = init: {
            var i_tags_types: []ULandType = &[_]ULandType{};
            for (templates, 0..) |template, i| {
                if (template.tags) |tags| {
                    if (tags.len == 0) @compileError("Template tags was empty, which is not allowed; rather use null. Template index: " ++ ct.itoa(i) ++ ".");
                    outer: for (tags, 0..) |tag, j| {
                        if (@sizeOf(tag) != 0) @compileError("Template tag wasn't a ZST, which is not allowed. Template index: " ++ ct.itoa(i) ++ ", tag index: " ++ ct.itoa(j));
                        const uLandType = ULandType.get(tag);
                        for (i_tags_types) |existing_ULandType| {
                            if (uLandType.type == existing_ULandType.type) continue :outer;
                        }

                        i_tags_types = @constCast(i_tags_types ++ .{uLandType});
                    }
                }
            }

            break :init i_tags_types;
        };

        pub const ComponentBitset = std.bit_set.StaticBitSet(component_types.len);
        pub const TagBitset = std.bit_set.StaticBitSet(tags_types.len);

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .archetypes = init: {
                    var archetypes: @FieldType(Self, "archetypes") = undefined;
                    inline for (0..templates.len) |i| {
                        archetypes[i] = .init;
                    }

                    break :init archetypes;
                },
                .entity_to_archetype_map = .empty,
                .unused_entitys = .empty,
                .destroyed_entitys = .empty,
                .singletons = .empty,
                .singleton_to_entity_map = .empty,
                .entity_count = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (0..templates.len) |i| {
                self.archetypes[i].deinit(self.allocator);
            }

            self.entity_to_archetype_map.deinit(self.allocator);
            self.unused_entitys.deinit(self.allocator);
            self.destroyed_entitys.deinit(self.allocator);

            self.singletons.deinit(self.allocator);
            self.singleton_to_entity_map.deinit(self.allocator);
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entity_to_archetype_map.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn getEntityPointer(self: *Self, entity: EntityType) !EntityPointer {
            if (self.entity_to_archetype_map.get(entity)) |archetypePtr| {
                return .{ .entity = entity, .generation = archetypePtr.generation };
            }

            return error.MissingEntity;
        }

        pub fn createEntity(self: *Self, comptime template: Template, components: ct.TupleOfItems(template.components)) EntityPointer {
            const new_entity: EntityType, const generation: GenerationType = init: {
                if (self.unused_entitys.items.len > 0) {
                    const entity_ptr = self.unused_entitys.pop().?;
                    break :init .{ entity_ptr.entity, GenerationType.make(entity_ptr.generation.value() + 1) };
                }

                self.entity_count += 1;
                break :init .{ EntityType.make(self.entity_count - 1), GenerationType.make(0) };
            };

            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tag_bitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const archetype_index: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((@TypeOf(archetype).tag_bitset.eql(tag_bitset) and @TypeOf(archetype).component_bitset.eql(component_bitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            if (ct.TupleOfItems(template.components) == ct.TupleOfItems(self.archetypes[archetype_index].template.components)) {
                self.archetypes[archetype_index].append(new_entity, components, self.allocator) catch unreachable;
                self.entity_to_archetype_map.put(self.allocator, new_entity, .{ .archetype = ArchetypeType.make(@intCast(archetype_index)), .generation = generation }) catch unreachable;
            } else {
                // NOTE: User was not kind.
                const new_components: ct.TupleOfItems(self.archetypes[archetype_index].template.components) = init: {
                    var new_components: ct.TupleOfItems(self.archetypes[archetype_index].template.components) = undefined;
                    outer: inline for (self.archetypes[archetype_index].template.components, 0..) |aComponent, j| {
                        inline for (template.components, 0..) |uComponent, k| {
                            if (aComponent == uComponent) {
                                new_components[j] = components[k];
                                continue :outer;
                            }
                        }
                    }

                    break :init new_components;
                };

                self.archetypes[archetype_index].append(new_entity, new_components, self.allocator) catch unreachable;
                self.entity_to_archetype_map.put(self.allocator, new_entity, .{ .archetype = ArchetypeType.make(@intCast(archetype_index)), .generation = generation }) catch unreachable;
            }

            return EntityPointer{ .entity = new_entity, .generation = generation };
        }

        pub fn destroyEntity(self: *Self, entity: EntityType) void {
            self.destroyed_entitys.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destroyed_entitys.items) |entity| {
                const archetype_ptr = self.entity_to_archetype_map.get(entity).?;
                inline for (0..self.archetypes.len) |i| {
                    if (i == archetype_ptr.archetype.value()) {
                        self.archetypes[i].remove(entity, self.allocator) catch unreachable;
                    }
                }

                std.debug.assert(self.entity_to_archetype_map.remove(entity));

                self.unused_entitys.append(self.allocator, EntityPointer{ .entity = entity, .generation = archetype_ptr.generation }) catch unreachable;
            }

            self.destroyed_entitys.clearAndFree(self.allocator);
        }

        pub fn entityHasComponent(
            self: *Self,
            entity: EntityType,
            comptime component: type,
        ) bool {
            const archetype_index: u32 = self.entity_to_archetype_map.get(entity).?.archetype.value();
            const component_id = comptime comptimeGetComponentId(component);

            inline for (self.archetypes, 0..) |archetype, i| {
                if (i == archetype_index) {
                    return @TypeOf(archetype).component_bitset.isSet(component_id);
                }
            }

            unreachable; // NOTE: Would mean that entity exists in an archetype that isn't in archetypes.
        }

        pub fn entityHasTag(
            self: *Self,
            entity: EntityType,
            comptime tag: type,
        ) bool {
            const archetype_index: u32 = self.entity_to_archetype_map.get(entity).?.archetype.value();
            const tag_id = comptime comptimeGetTagId(tag);

            inline for (self.archetypes, 0..) |archetype, i| {
                if (i == archetype_index) {
                    return @TypeOf(archetype).tag_bitset.isSet(tag_id);
                }
            }

            unreachable; // NOTE: Would mean that entity exists in an archetype that isn't in archetypes.
        }

        pub fn getEntityComponent(
            self: *Self,
            entity: EntityType,
            comptime component: type,
        ) !*component {
            const archetype_index: u32 = self.entity_to_archetype_map.get(entity).?.archetype.value();
            inline for (self.archetypes, 0..) |archetype, i| {
                if (i == archetype_index) {
                    if (comptime archetype.template.hasComponent(component)) {
                        const columnIndex = comptime archetype.template.getComponentIndex(component);
                        return &archetype.tuple_array_list.tuple_of_many_ptrs[columnIndex][archetype.entity_to_row_map.get(entity).?.value()];
                    }
                    return error.ComponentNotFound;
                }
            }

            return error.ComponentNotFound;
        }

        // FIXME: Check that the entity doesn't already have this component.

        /// This will transfer entity from one archetype to another, but this will require an existing component.
        pub fn addComponentToEntity(self: *Self, entity: EntityType, comptime T: type, component: T) !void {
            const old_archetype_index, const generation = init: {
                const archetype_ptrs = self.entity_to_archetype_map.get(entity).?;

                break :init .{ archetype_ptrs.archetype.value(), archetype_ptrs.generation };
            };
            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(&.{T});

            outer: inline for (0..self.archetypes.len) |i| {
                if (i == old_archetype_index) {
                    const new_component_bitset = comptime @TypeOf(self.archetypes[i]).component_bitset.unionWith(component_bitset);
                    const new_archetype_index = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).component_bitset.eql(new_component_bitset) and
                                @TypeOf(self.archetypes[j]).tag_bitset.eql(@TypeOf(self.archetypes[i]).tag_bitset))
                            {
                                break :init j;
                            }
                        }

                        break :outer; // NOTE: THIS BRANCH IS INVALID!
                    };

                    const components = init: {
                        const old_components = self.archetypes[i].popRemove(entity, self.allocator) catch unreachable;
                        var components: ct.TupleOfItems(self.archetypes[new_archetype_index].template.components) = undefined;
                        inline for (self.archetypes[i].template.components, 0..) |comp, j| {
                            components[comptime self.archetypes[new_archetype_index].template.getComponentIndex(comp)] = old_components[j];
                        }

                        components[comptime self.archetypes[new_archetype_index].template.getComponentIndex(T)] = component;

                        break :init components;
                    };

                    self.entity_to_archetype_map.put(self.allocator, entity, .{ .archetype = ArchetypeType.make(@intCast(new_archetype_index)), .generation = generation }) catch unreachable;
                    self.archetypes[new_archetype_index].append(entity, components, self.allocator) catch unreachable;
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        pub fn removeComponentFromEntity(self: *Self, entity: EntityType, comptime T: type) !void {
            const old_archetype_index, const generation = init: {
                const archetype_ptrs = self.entity_to_archetype_map.get(entity).?;

                break :init .{ archetype_ptrs.archetype.value(), archetype_ptrs.generation };
            };

            outer: inline for (0..self.archetypes.len) |i| {
                if (i == old_archetype_index) {
                    const new_component_bitset = comptime init: {
                        var new_component_bitset: ComponentBitset = @TypeOf(self.archetypes[i]).component_bitset;
                        new_component_bitset.unset(comptimeGetComponentId(T));
                        break :init new_component_bitset;
                    };

                    const new_archetype_index = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).component_bitset.eql(new_component_bitset) and
                                @TypeOf(self.archetypes[j]).tag_bitset.eql(@TypeOf(self.archetypes[i]).tag_bitset))
                            {
                                break :init j;
                            }
                        }

                        break :outer; // NOTE: THIS BRANCH IS INVALID!
                    };

                    const components = init: {
                        const old_components = self.archetypes[i].popRemove(entity, self.allocator) catch unreachable;
                        var components: ct.TupleOfItems(self.archetypes[new_archetype_index].template.components) = undefined;
                        inline for (self.archetypes[new_archetype_index].template.components, 0..) |comp, j| {
                            components[j] = old_components[comptime self.archetypes[i].template.getComponentIndex(comp)];
                        }

                        break :init components;
                    };

                    self.entity_to_archetype_map.put(self.allocator, entity, .{ .archetype = ArchetypeType.make(@intCast(new_archetype_index)), .generation = generation }) catch unreachable;
                    self.archetypes[new_archetype_index].append(entity, components, self.allocator) catch unreachable;
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        // FIXME: check if the entity already has this tag.

        pub fn addTagToEntity(self: *Self, entity: EntityType, comptime tag: type) !void {
            const old_archetype_index, const generation = init: {
                const archetype_ptrs = self.entity_to_archetype_map.get(entity).?;

                break :init .{ archetype_ptrs.archetype.value(), archetype_ptrs.generation };
            };
            const tag_bitset: TagBitset = comptime comptimeGetTagBitset(&.{tag});

            outer: inline for (0..self.archetypes.len) |i| {
                if (i == old_archetype_index) {
                    const new_tag_bitset = comptime @TypeOf(self.archetypes[i]).tag_bitset.unionWith(tag_bitset);
                    const new_archetype_index = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).component_bitset.eql(@TypeOf(self.archetypes[i]).component_bitset) and
                                @TypeOf(self.archetypes[j]).tag_bitset.eql(new_tag_bitset))
                            {
                                break :init j;
                            }
                        }

                        break :outer; // NOTE: THIS BRANCH IS INVALID!
                    };

                    const components = init: {
                        const old_components = self.archetypes[i].popRemove(entity, self.allocator) catch unreachable;
                        var components: ct.TupleOfItems(self.archetypes[new_archetype_index].template.components) = undefined;
                        inline for (self.archetypes[i].template.components, 0..) |comp, j| {
                            components[comptime self.archetypes[new_archetype_index].template.getComponentIndex(comp)] = old_components[j];
                        }

                        break :init components;
                    };

                    self.entity_to_archetype_map.put(self.allocator, entity, .{ .archetype = ArchetypeType.make(@intCast(new_archetype_index)), .generation = generation }) catch unreachable;
                    self.archetypes[new_archetype_index].append(entity, components, self.allocator) catch unreachable;
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        // FIXME: check if the entity actually has this tag so we can remove it.
        pub fn removeTagFromEntity(self: *Self, entity: EntityType, comptime tag: type) !void {
            const old_archetype_index, const generation = init: {
                const archetype_ptrs = self.entity_to_archetype_map.get(entity).?;

                break :init .{ archetype_ptrs.archetype.value(), archetype_ptrs.generation };
            };

            outer: inline for (0..self.archetypes.len) |i| {
                if (i == old_archetype_index) {
                    const new_tag_bitset = comptime init: {
                        var new_tag_bitset = @TypeOf(self.archetypes[i]).tag_bitset;
                        new_tag_bitset.unset(comptimeGetTagId(tag));

                        break :init new_tag_bitset;
                    };

                    const new_archetype_index = comptime init: {
                        for (0..self.archetypes.len) |j| {
                            if (@TypeOf(self.archetypes[j]).component_bitset.eql(@TypeOf(self.archetypes[i]).component_bitset) and
                                @TypeOf(self.archetypes[j]).tag_bitset.eql(new_tag_bitset))
                            {
                                break :init j;
                            }
                        }

                        break :outer; // NOTE: THIS BRANCH IS INVALID!
                    };

                    const components = init: {
                        const old_components = self.archetypes[i].popRemove(entity, self.allocator) catch unreachable;
                        var components: ct.TupleOfItems(self.archetypes[new_archetype_index].template.components) = undefined;
                        inline for (self.archetypes[i].template.components, 0..) |comp, j| {
                            components[comptime self.archetypes[new_archetype_index].template.getComponentIndex(comp)] = old_components[j];
                        }

                        break :init components;
                    };

                    self.entity_to_archetype_map.put(self.allocator, entity, .{ .archetype = ArchetypeType.make(@intCast(new_archetype_index)), .generation = generation }) catch unreachable;
                    self.archetypes[new_archetype_index].append(entity, components, self.allocator) catch unreachable;
                    return;
                }
            }

            return error.NoMatchingArchetype;
        }

        pub fn comptimeGetComponentBitset(comptime components: []const type) ComponentBitset {
            var bitset: ComponentBitset = .initEmpty();
            outer: for (components) |component| {
                const u_land_type = ULandType.get(component);
                for (component_types, 0..) |existing_component, i| {
                    if (u_land_type.eql(existing_component)) {
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

        pub fn comptimeGetComponentId(comptime component: type) usize {
            const u_land_type = ULandType.get(component);
            for (component_types, 0..) |existing_component, i| {
                if (u_land_type.eql(existing_component)) {
                    return i;
                }
            }

            @compileError("Was given a component " ++ @typeName(component) ++ ", that wasn't known by the ECS.");
        }

        pub fn comptimeGetTagBitset(comptime tags: []const type) TagBitset {
            var bitset: TagBitset = .initEmpty();
            outer: for (tags) |tag| {
                const u_land_type = ULandType.get(tag);
                for (tags_types, 0..) |existing_component, i| {
                    if (u_land_type.eql(existing_component)) {
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

        pub fn comptimeGetTagId(comptime tag: type) usize {
            const u_land_type = ULandType.get(tag);
            for (tags_types, 0..) |existing_component, i| {
                if (u_land_type.eql(existing_component)) {
                    return i;
                }
            }

            @compileError("Was given a tag " ++ @typeName(tag) ++ ", that wasn't known by the ECS.");
        }

        fn getMeantArchetypeTemplate(template: Template) Template {
            for (templates) |temp| {
                if (temp.eql(template)) return temp;
            }

            @compileError("Supplied template didn't have a corresponding archetype.");
        }

        pub fn getArchetype(self: *Self, comptime template: Template) init: {
            const m_template = getMeantArchetypeTemplate(template);
            break :init *Archetype(
                m_template,
                component_types.len,
                comptimeGetComponentBitset(m_template.components),
                tags_types.len,
                if (m_template.tags) |tags| comptimeGetTagBitset(tags) else TagBitset.initEmpty(),
            );
        } {
            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tag_bitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const archetype_index: usize = comptime init: {
                for (self.archetypes, 0..) |archetype, i| {
                    if ((@TypeOf(archetype).tag_bitset.eql(tag_bitset) and @TypeOf(archetype).component_bitset.eql(component_bitset))) break :init i;
                }

                @compileError("Supplied template didn't have a corresponding archetype.");
            };

            return &self.archetypes[archetype_index];
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getIterator(self: *Self, comptime component: type, comptime @"tags?": ?[]const type, comptime exclude: Template) ?Iterator(component) {
            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(&.{component});
            const tag_bitset: TagBitset = comptime (if (@"tags?") |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const exclude_component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(exclude.components);
            const exclude_tag_bitset: TagBitset = comptime (if (exclude.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const matching_archetype_indices: []const usize = comptime init: {
                var matching_archetype_indices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (@TypeOf(archetype).component_bitset.intersectWith(component_bitset).eql(component_bitset) and
                        @TypeOf(archetype).tag_bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                        @TypeOf(archetype).component_bitset.intersectWith(exclude_component_bitset).eql(ComponentBitset.initEmpty()) and
                        @TypeOf(archetype).tag_bitset.intersectWith(exclude_tag_bitset).eql(TagBitset.initEmpty()))
                    {
                        matching_archetype_indices = @constCast(matching_archetype_indices ++ .{i});
                    }
                }
                if (matching_archetype_indices.len == 0) @compileError("No matching archetypes with the supplied include and exclude.");
                break :init matching_archetype_indices;
            };

            var component_arrays: std.ArrayListUnmanaged([]component) = .empty;
            errdefer component_arrays.deinit(self.allocator);

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            inline for (matching_archetype_indices) |index| {
                if (self.archetypes[index].tuple_array_list.count > 0) {
                    const array = self.archetypes[index].tuple_array_list.getItemArray(component);
                    component_arrays.append(self.allocator, array) catch unreachable;
                    entitys.append(self.allocator, self.archetypes[index].entitys.items) catch unreachable;
                }
            }

            if (component_arrays.items.len == 0) {
                return null;
            }

            return Iterator(component).init(component_arrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getTupleIterator(self: *Self, comptime template: Template, comptime exclude: Template) ?TupleIterator(template.components) {
            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(template.components);
            const tag_bitset: TagBitset = comptime (if (template.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const exclude_component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(exclude.components);
            const exclude_tag_bitset: TagBitset = comptime (if (exclude.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());

            const matching_archetype_indices: []const usize = comptime init: {
                var matching_archetype_indices: []usize = &[_]usize{};
                for (self.archetypes, 0..) |archetype, i| {
                    if (@TypeOf(archetype).component_bitset.intersectWith(component_bitset).eql(component_bitset) and
                        @TypeOf(archetype).tag_bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                        @TypeOf(archetype).component_bitset.intersectWith(exclude_component_bitset).eql(ComponentBitset.initEmpty()) and
                        @TypeOf(archetype).tag_bitset.intersectWith(exclude_tag_bitset).eql(TagBitset.initEmpty()))
                    {
                        matching_archetype_indices = @constCast(matching_archetype_indices ++ .{i});
                    }
                }
                if (matching_archetype_indices.len == 0) @compileError("No matching archetypes with the supplied include and exclude.");
                break :init matching_archetype_indices;
            };

            var tuple_of_arraylist: TupleOfSliceArrayLists(template.components) = init: {
                var tuple_of_arraylist: TupleOfSliceArrayLists(template.components) = undefined;
                inline for (0..template.components.len) |i| {
                    tuple_of_arraylist[i] = .empty;
                }

                break :init tuple_of_arraylist;
            };

            errdefer {
                inline for (0..tuple_of_arraylist.len) |i| {
                    tuple_of_arraylist[i].deinit(self.allocator);
                }
            }

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            inline for (matching_archetype_indices) |index| {
                inline for (template.components, 0..) |component, j| {
                    if (self.archetypes[index].tuple_array_list.count > 0) {
                        const array = self.archetypes[index].tuple_array_list.getItemArray(component);
                        tuple_of_arraylist[j].append(self.allocator, array) catch unreachable;
                        if (comptime j == 0) entitys.append(self.allocator, self.archetypes[index].entitys.items) catch unreachable;
                    }
                }
            }

            if (tuple_of_arraylist[0].items.len == 0) {
                return null;
            }

            const tuple_of_buffers: TupleOfBuffers(template.components) = init: {
                var tuple_of_buffers: TupleOfBuffers(template.components) = undefined;
                inline for (0..template.components.len) |i| {
                    tuple_of_buffers[i] = tuple_of_arraylist[i].toOwnedSlice(self.allocator) catch unreachable;
                }

                break :init tuple_of_buffers;
            };

            errdefer {
                inline for (tuple_of_buffers) |buffer| {
                    self.allocator.free(buffer);
                }
            }

            return TupleIterator(template.components).init(tuple_of_buffers, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        pub fn createSingleton(self: *Self, requirements: Template) SingletonType {
            const component_bitset: ComponentBitset = comptime comptimeGetComponentBitset(requirements.components);
            const tag_bitset: TagBitset = comptime (if (requirements.tags) |tags| comptimeGetTagBitset(tags) else .initEmpty());
            comptime check: {
                for (self.archetypes) |archetype| {
                    if (@TypeOf(archetype).component_bitset.intersectWith(component_bitset).eql(component_bitset) and
                        @TypeOf(archetype).tag_bitset.intersectWith(tag_bitset).eql(tag_bitset))
                    {
                        break :check;
                    }
                }

                @compileError("No matching archetype");
            }

            self.singletons.append(self.allocator, .{ component_bitset, tag_bitset }) catch unreachable;
            return SingletonType.make(@intCast(self.singletons.items.len - 1));
        }

        pub fn setSingletonsEntity(self: *Self, singleton: SingletonType, entityPtr: EntityPointer) !void {
            std.debug.assert(singleton.value() < self.singletons.items.len);
            const component_bitset, const tag_bitset = self.singletons.items[singleton.value()];

            inline for (self.archetypes) |archetype| {
                if (@TypeOf(archetype).component_bitset.intersectWith(component_bitset).eql(component_bitset) and
                    @TypeOf(archetype).tag_bitset.intersectWith(tag_bitset).eql(tag_bitset))
                {
                    if (archetype.entity_to_row_map.get(entityPtr.entity) != null) {
                        self.singleton_to_entity_map.put(self.allocator, singleton, entityPtr) catch unreachable;
                        return;
                    }
                }
            }

            return error.EntityNotMatchRequirments;
        }

        pub fn getSingletonsEntity(self: *Self, singleton: SingletonType) ?EntityPointer {
            std.debug.assert(singleton.value() < self.singletons.items.len);
            if (self.singleton_to_entity_map.get(singleton)) |entity| {
                if (self.entity_to_archetype_map.get(entity.entity)) |_| {
                    return entity;
                }

                std.debug.assert(self.singleton_to_entity_map.remove(singleton));
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);
    defer ecs.deinit();

    const EcsType: type = @TypeOf(ecs);

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(0);
        const component_bitset = comptime EcsType.comptimeGetComponentBitset(&.{Position});
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(0);
        expected.set(1);
        const component_bitset = comptime EcsType.comptimeGetComponentBitset(&.{ Position, Collider });
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.ComponentBitset.initEmpty();
        expected.set(1);
        const component_bitset = comptime EcsType.comptimeGetComponentBitset(&.{Collider});
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.TagBitset.initEmpty();
        expected.set(0);
        const tag_bitset = comptime EcsType.comptimeGetTagBitset(&.{Tag});
        try std.testing.expect(expected.eql(tag_bitset));
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
    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &.{ Collider, Position }, .tags = &.{Tag} },
            .{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } },
        );
        _ = ecs.createEntity(
            .{ .components = &.{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    const archetype = ecs.getArchetype(.{ .components = &.{ Collider, Position }, .tags = &.{Tag} });

    try std.testing.expect(archetype.tuple_array_list.count == 100);

    const positions = archetype.tuple_array_list.getItemArray(Position);

    for (positions) |item| {
        try std.testing.expect(item.x == 4);
        try std.testing.expect(item.y == 4);
    }

    const colliders = archetype.tuple_array_list.getItemArray(Collider);
    for (colliders) |item| {
        try std.testing.expect(item.x == 5);
        try std.testing.expect(item.y == 5);
    }
}

test "Removing entity's component" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 1, .y = 1 } },
        );

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try ecs.removeComponentFromEntity(entity.entity, Collider);
        }

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(!ecs.entityHasComponent(entity.entity, Collider));
        }
    }
}

test "Adding a component to entity" {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &.{Position}, .tags = &.{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try ecs.addComponentToEntity(entity.entity, Collider, .{ .x = 1, .y = 0 });
        }

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHasComponent(entity.entity, Collider));
            const collider = try ecs.getEntityComponent(entity.entity, Collider);
            try std.testing.expectEqual(Collider{ .x = 1, .y = 0 }, collider.*);
        }
    }
}

test "Adding a tag to entity" {
    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&.{
        .{ .components = &.{Position}, .tags = &.{Tag} },
        .{ .components = &.{Position}, .tags = null },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &.{Position}, .tags = &.{} },
            .{Position{ .x = 1, .y = 1 }},
        );

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try std.testing.expect(!ecs.entityHasTag(entity.entity, Tag));
            try ecs.addTagToEntity(entity.entity, Tag);
        }

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHasTag(entity.entity, Tag));
        }
    }
}

test "Removing a tag from entity" {
    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};
    var ecs: Ecs(&.{
        .{ .components = &.{Position}, .tags = &.{Tag} },
        .{ .components = &.{Position}, .tags = null },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &.{Position}, .tags = &.{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHasTag(entity.entity, Tag));
            try ecs.removeTagFromEntity(entity.entity, Tag);
        }

        {
            const position = try ecs.getEntityComponent(entity.entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try std.testing.expect(!ecs.entityHasTag(entity.entity, Tag));
        }
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
    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ .components = &.{Position} },
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
        .{ .components = &.{ Collider, Position }, .tags = &.{Tag} },
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    const entityPtr = ecs.createEntity(
        .{ .components = &.{Position} },
        .{Position{ .x = 1, .y = 1 }},
    );

    try std.testing.expect(ecs.entityIsValid(entityPtr) == true);

    ecs.destroyEntity(entityPtr.entity);

    ecs.clearDestroyedEntitys();
    try std.testing.expect(ecs.destroyed_entitys.items.len == 0);
    try std.testing.expect(ecs.unused_entitys.items.len == 1);

    try std.testing.expect(ecs.entityIsValid(entityPtr) == false);

    const entityPtr2 = ecs.createEntity(
        .{ .components = &.{Position} },
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &.{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &.{Position}, .tags = &.{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{}).?;
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

    var iterator2: Iterator(Position) = ecs.getIterator(Position, null, .{ .tags = &.{Tag} }).?;
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
        );
    }

    {
        var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{}).?;
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

        var iterator: Iterator(Position) = ecs.getIterator(Position, null, .{}).?;
        defer iterator.deinit();
        if (iterator.next()) |_| {
            try std.testing.expect(iterator.current_entity.value() == 99);
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
            .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
        );
        _ = ecs.createEntity(
            .{ .components = &.{Position} },
            .{Position{ .x = 1, .y = 1 }},
        );
        _ = ecs.createEntity(
            .{ .components = &.{Position}, .tags = &.{Tag} },
            .{Position{ .x = 1, .y = 1 }},
        );
    }

    var iterator: TupleIterator(&.{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &.{ Position, Collider } },
        .{ .components = &.{} },
    ).?;
    defer iterator.deinit();

    try std.testing.expect(iterator.tuple_of_buffers[0].len == 1);
    try std.testing.expect(iterator.tuple_of_buffers[0][0].len == 100);

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 6);
        try std.testing.expect(components[0].y == 5);
        components[0].x = 7;
        components[0].y = 7;
    }

    var iterator2: TupleIterator(&.{ Position, Collider }) = ecs.getTupleIterator(
        .{ .components = &.{ Position, Collider } },
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

    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    const entity1 = ecs.createEntity(
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
    );
    const entity2 = ecs.createEntity(
        .{ .components = &.{Position} },
        .{Position{ .x = 1, .y = 1 }},
    );
    const entity3 = ecs.createEntity(
        .{ .components = &.{Position}, .tags = &.{Tag} },
        .{Position{ .x = 1, .y = 1 }},
    );

    {
        const singleton = ecs.createSingleton(.{ .components = &.{Position}, .tags = &.{Tag} });
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
        const singleton = ecs.createSingleton(.{ .components = &.{Position} });
        try std.testing.expect(ecs.getSingletonsEntity(singleton) == null);

        ecs.setSingletonsEntity(singleton, entity1) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        ecs.setSingletonsEntity(singleton, entity2) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity2.entity);

        ecs.setSingletonsEntity(singleton, entity3) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity3.entity);
    }
}
