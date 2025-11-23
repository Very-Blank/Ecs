const std = @import("std");
const ct = @import("comptimeTypes.zig");

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const GenericIterator = @import("iterator.zig").GenericIterator;
const GenericTupleIterator = @import("tupleIterator.zig").GenericTupleIterator;

const TupleOfBuffers = @import("comptimeTypes.zig").TupleOfBuffers;

pub const Template: type = struct {
    components: []const type = &.{},
    tags: []const type = &.{},

    pub fn eql(self: *const Template, other: Template) bool {
        if (self.components.len != other.components.len) return false;

        outer: for (self.components) |component| {
            for (other.components) |component2| {
                if (component == component2) continue :outer;
            }

            return false;
        }

        if (self.tags.len != other.tags.len) return false;

        outer: for (self.tags) |tag| {
            for (other.tags) |tag2| {
                if (tag == tag2) continue :outer;
            }

            return false;
        }

        return true;
    }
};

pub const TupleFilter = struct {
    include: Template,
    exclude: Template = .{},
};

pub const Filter = struct {
    component: type,
    tags: []const type = &.{},
    exclude: Template = .{},
};

pub fn NonExhaustiveEnum(comptime T: type, comptime Unique: type) type {
    ok: {
        @"error": {
            switch (@typeInfo(T)) {
                .int => |info| if (info.signedness != .unsigned) break :@"error",
                else => break :@"error",
            }

            switch (@typeInfo(Unique)) {
                .@"opaque" => break :ok,
                else => break :@"error",
            }
        }

        @compileError("Unexpected type was given: " ++ @typeName(T) ++ ", expected an unsiged integer.");
    }

    return enum(T) {
        _,

        const Self = @This();
        const _unique = Unique;

        pub inline fn make(int: T) Self {
            return @enumFromInt(int);
        }

        pub inline fn value(@"enum": Self) T {
            return @intFromEnum(@"enum");
        }
    };
}

pub const EntityType = NonExhaustiveEnum(u32, opaque {});
pub const GenerationType = NonExhaustiveEnum(u32, opaque {});
pub const SingletonType = NonExhaustiveEnum(u32, opaque {});

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

    for (templates, 0..) |template, i| {
        for (i + 1..templates.len) |j| {
            if (template.eql(templates[j])) @compileError("Two templates where the same which is not allowed. Template one index: " ++ ct.itoa(i) ++ ", template two index: " ++ ct.itoa(j));
        }
    }

    for (templates, 0..) |template, i| {
        if (template.components.len == 0) @compileError("Template components was empty, which is not allowed. Template index: " ++ ct.itoa(i) ++ ".");

        for (0..template.components.len) |cur_component_index| {
            if (@sizeOf(template.components[cur_component_index]) == 0)
                @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ ct.itoa(cur_component_index) ++ ", component: " ++ @typeName(template.components[cur_component_index]));

            for (cur_component_index + 1..template.components.len) |nex_component_index| {
                if (template.components[cur_component_index] == template.components[nex_component_index])
                    @compileError("Template had two of the same component. Template index: " ++ ct.itoa(i) ++ ", component: " ++ @typeName(template.components[cur_component_index]));
            }
        }

        for (0..template.tags.len) |cur_tag_index| {
            if (@sizeOf(template.tags[cur_tag_index]) != 0)
                @compileError("Templates tag wasn't a ZST, which is not allowed. Template index: " ++ ct.itoa(cur_tag_index) ++ ", tag: " ++ @typeName(template.tags[cur_tag_index]));

            for (cur_tag_index + 1..template.tags.len) |nex_tag_index| {
                if (template.tags[cur_tag_index] == template.tags[nex_tag_index])
                    @compileError("Template had two of the same tag. Template index: " ++ ct.itoa(i) ++ ", tag: " ++ @typeName(template.tags[cur_tag_index]));
            }
        }
    }

    return struct {
        archetypes: init: {
            var newFields: [templates.len]std.builtin.Type.StructField = undefined;

            for (templates, 0..) |template, i| {
                const archetype_type: type = Archetype(
                    template,
                    ResourceRegistry.Components.types.len,
                    ResourceRegistry.Components.getBitset(template.components),
                    ResourceRegistry.Tags.types.len,
                    ResourceRegistry.Tags.getBitset(template.tags),
                );

                newFields[i] = std.builtin.Type.StructField{
                    .name = ct.itoa(i),
                    .type = archetype_type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(archetype_type),
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
        unused_entitys: std.ArrayList(EntityPointer),
        destroyed_entitys: std.ArrayList(EntityPointer),

        singletons: std.ArrayList(Singleton),
        singleton_to_entity_map: std.AutoHashMapUnmanaged(SingletonType, EntityPointer),

        entity_count: u32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub const Singleton = struct { ResourceRegistry.Components.Bitset, ResourceRegistry.Tags.Bitset };

        pub const ResourceRegistry = struct {
            fn getUniqueTypeCount(comptime field: []const u8) usize {
                var count: usize = 0;

                for (templates) |template| {
                    count += @field(template, field).len;
                }

                for (templates, 0..) |template, i| {
                    item_iterator: for (@field(template, field)) |new_item| {
                        for (0..i) |j| {
                            for (@field(templates[j], field)) |old_item| {
                                if (old_item == new_item) continue :item_iterator;
                            }
                        }

                        // NOTE: Each template should only have one of each component or tag.
                        next_template: for (i + 1..templates.len) |j| {
                            for (@field(templates[j], field)) |next_item| {
                                if (new_item == next_item) {
                                    count -= 1;
                                    continue :next_template;
                                }
                            }
                        }
                    }
                }

                return count;
            }

            fn Registry(field: []const u8) type {
                return struct {
                    const len = getUniqueTypeCount(field);

                    pub const types: [len]type = init: {
                        var init_types: [len]type = undefined;
                        var i: usize = 0;

                        for (templates) |template| {
                            inner: for (@field(template, field)) |@"type"| {
                                for (0..i) |j| {
                                    if (init_types[j] == @"type") continue :inner;
                                }

                                init_types[i] = @"type";
                                i += 1;
                            }
                        }

                        if (i != init_types.len) @compileError("The calculated count of unique " ++ field ++ " was incorrect.");
                        break :init init_types;
                    };

                    pub const Bitset = std.bit_set.StaticBitSet(len);

                    pub fn getBitset(comptime included_types: []const type) Bitset {
                        var bitset: Bitset = .initEmpty();
                        outer: for (included_types) |@"type"| {
                            for (types, 0..) |existing_type, i| {
                                if (existing_type == @"type") {
                                    if (bitset.isSet(i)) {
                                        @compileError(.{std.ascii.toUpper(field[0])} ++ field[1..field.len] ++ " had two of the same " ++ field[0 .. field.len - 1] ++ " " ++ @typeName(@"type") ++ ", Which is not allowed.");
                                    }

                                    bitset.set(i);
                                    continue :outer;
                                }
                            }

                            @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(@"type") ++ ", that wasn't known by the ECS.");
                        }

                        return bitset;
                    }

                    pub fn getId(comptime @"type": type) usize {
                        for (types, 0..) |existing_component, i| {
                            if (existing_component == @"type") {
                                return i;
                            }
                        }

                        @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(@"type") ++ ", that wasn't known by the ECS.");
                    }
                };
            }

            pub const Components = Registry("components");

            pub const Tags = Registry("tags");

            pub const Archetypes = struct {
                pub fn getIndexByBitsets(component_bitset: Components.Bitset, tag_bitset: Tags.Bitset) !ArchetypeType {
                    for (@typeInfo(@FieldType(Self, "archetypes")).@"struct".fields, 0..) |archetype_field, i| {
                        if (archetype_field.type.Components.bitset.eql(component_bitset) and
                            archetype_field.type.Tags.bitset.eql(tag_bitset))
                            return ArchetypeType.make(@intCast(i));
                    }

                    return error.ArchetypeDoesNotExist;
                }

                pub fn getIndexByTemplate(template: Template) !ArchetypeType {
                    return try getIndexByBitsets(Components.getBitset(template.components), Tags.getBitset(template.tags));
                }

                pub fn matchingIndexCount(
                    include_components: []const type,
                    include_tags: []const type,
                    exclude_components: []const type,
                    exclude_tags: []const type,
                ) usize {
                    const component_bitset: Components.Bitset = Components.getBitset(include_components);
                    const tag_bitset: Tags.Bitset = Tags.getBitset(include_tags);

                    const exclude_component_bitset: Components.Bitset = Components.getBitset(exclude_components);
                    const exclude_tag_bitset: Tags.Bitset = Tags.getBitset(exclude_tags);

                    var matching_archetype_count: usize = 0;
                    for (@typeInfo(@FieldType(Self, "archetypes")).@"struct".fields) |archetype_field| {
                        if (archetype_field.type.Components.bitset.intersectWith(component_bitset).eql(component_bitset) and
                            archetype_field.type.Tags.bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                            archetype_field.type.Components.bitset.intersectWith(exclude_component_bitset).eql(Components.Bitset.initEmpty()) and
                            archetype_field.type.Tags.bitset.intersectWith(exclude_tag_bitset).eql(Tags.Bitset.initEmpty()))
                        {
                            matching_archetype_count += 1;
                        }
                    }

                    if (matching_archetype_count == 0) @compileError("No matching archetypes with the supplied include and exclude.");

                    return matching_archetype_count;
                }

                pub fn matchingIndices(
                    include_components: []const type,
                    include_tags: []const type,
                    exclude_components: []const type,
                    exclude_tags: []const type,
                ) [matchingIndexCount(include_components, include_tags, exclude_components, exclude_tags)]ArchetypeType {
                    const component_bitset: Components.Bitset = Components.getBitset(include_components);
                    const tag_bitset: Tags.Bitset = Tags.getBitset(include_tags);

                    const exclude_component_bitset: Components.Bitset = Components.getBitset(exclude_components);
                    const exclude_tag_bitset: Tags.Bitset = Tags.getBitset(exclude_tags);

                    const matching_archetype_count: usize = init: {
                        var matching_archetype_count = 0;
                        for (@typeInfo(@FieldType(Self, "archetypes")).@"struct".fields) |archetype_field| {
                            if (archetype_field.type.Components.bitset.intersectWith(component_bitset).eql(component_bitset) and
                                archetype_field.type.Tags.bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                                archetype_field.type.Components.bitset.intersectWith(exclude_component_bitset).eql(Components.Bitset.initEmpty()) and
                                archetype_field.type.Tags.bitset.intersectWith(exclude_tag_bitset).eql(Tags.Bitset.initEmpty()))
                            {
                                matching_archetype_count += 1;
                            }
                        }

                        if (matching_archetype_count == 0) @compileError("No matching archetypes with the supplied include and exclude.");

                        break :init matching_archetype_count;
                    };

                    return init: {
                        var archetype_indices: [matching_archetype_count]ArchetypeType = undefined;
                        var i: usize = 0;

                        for (@typeInfo(@FieldType(Self, "archetypes")).@"struct".fields, 0..) |archetype_field, j| {
                            if (archetype_field.type.Components.bitset.intersectWith(component_bitset).eql(component_bitset) and
                                archetype_field.type.Tags.bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                                archetype_field.type.Components.bitset.intersectWith(exclude_component_bitset).eql(Components.Bitset.initEmpty()) and
                                archetype_field.type.Tags.bitset.intersectWith(exclude_tag_bitset).eql(Tags.Bitset.initEmpty()))
                            {
                                archetype_indices[i] = ArchetypeType.make(@intCast(j));
                                i += 1;
                            }
                        }

                        break :init archetype_indices;
                    };
                }
            };
        };

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

        // These are here so you don't accidently use the wrong type of enum type to access any of these. LIKE I DID!
        inline fn archetype(self: *Self, comptime archetype_type: ArchetypeType) *@TypeOf(self.archetypes[archetype_type.value()]) {
            return &self.archetypes[archetype_type.value()];
        }

        inline fn TypeOfArchetype(comptime archetype_type: ArchetypeType) type {
            return @typeInfo(@FieldType(Self, "archetypes")).@"struct".fields[archetype_type.value()].type;
        }

        inline fn singleton(self: *Self, singleton_type: SingletonType) Singleton {
            std.debug.assert(singleton_type.value() < self.singletons.items.len);
            return self.singletons.items[singleton_type.value()];
        }

        pub fn entityIsValid(self: *Self, entity_ptr: EntityPointer) bool {
            const archetype_ptr = self.entity_to_archetype_map.get(entity_ptr.entity) orelse return false;

            return archetype_ptr.generation == entity_ptr.generation;
        }

        fn getTypesFromTuple(tuple: type) []const type {
            const struct_info: std.builtin.Type.Struct = init: switch (@typeInfo(tuple)) {
                .@"struct" => |value| {
                    if (!value.is_tuple or value.fields.len == 0) @compileError("Components must be in a non empty tuple.");
                    break :init value;
                },
                else => @compileError("Was given " ++ @tagName(tuple) ++ ", expected a non empty tuple."),
            };

            var components: [struct_info.fields.len]type = undefined;
            for (0..struct_info.fields.len) |i| {
                components[i] = struct_info.fields[i].type;
            }

            return &components;
        }

        inline fn translateTupleToTuple(comptime current: []const type, current_tuple: ct.TupleOfItems(current), comptime target: []const type) ct.TupleOfItems(target) {
            if (current.len != target.len) @compileError("Was called with differing tuple sizes.");
            comptime order_check: {
                for (current, 0..) |current_type, i| {
                    if (current_type != target[i]) break :order_check;
                }

                @compileError("Was given two tuples that had the same order.");
            }

            comptime outer: for (current) |current_type| {
                for (target) |target_type| {
                    if (current_type == target_type) continue :outer;
                }

                @compileError("Was given two tuples that had different composition types.");
            };

            return init: {
                var new_components: ct.TupleOfItems(target) = undefined;
                outer: inline for (target, 0..) |target_type, i| {
                    inline for (current, 0..) |current_type, j| {
                        if (target_type == current_type) {
                            new_components[i] = current_tuple[j];
                            continue :outer;
                        }
                    }
                }

                break :init new_components;
            };
        }

        fn setEntity(
            self: *Self,
            entity_ptr: EntityPointer,
            components: anytype,
            comptime archetype_type: ArchetypeType,
        ) void {
            self.entity_to_archetype_map.put(
                self.allocator,
                entity_ptr.entity,
                .{ .archetype = archetype_type, .generation = entity_ptr.generation },
            ) catch unreachable;

            self.archetype(archetype_type).append(entity_ptr, components, self.allocator) catch unreachable;
        }

        pub fn createEntity(self: *Self, components: anytype, tags: []const type) EntityPointer {
            const template: Template = .{ .components = comptime getTypesFromTuple(@TypeOf(components)), .tags = tags };
            const entity_archetype: ArchetypeType = comptime ResourceRegistry.Archetypes.getIndexByTemplate(template) catch @compileError("Archetype matching required components and tags didn't exist.");

            const new_entity_ptr: EntityPointer = init: {
                if (self.unused_entitys.items.len > 0) {
                    const entity_ptr = self.unused_entitys.pop().?;
                    break :init .{ .entity = entity_ptr.entity, .generation = GenerationType.make(entity_ptr.generation.value() + 1) };
                }

                self.entity_count += 1;
                break :init .{ .entity = EntityType.make(self.entity_count - 1), .generation = GenerationType.make(0) };
            };

            self.setEntity(
                new_entity_ptr,
                if (comptime TypeOfArchetype(entity_archetype).Components.orderEql(template.components))
                    components
                else
                    translateTupleToTuple(template.components, components, &TypeOfArchetype(entity_archetype).Components.types),
                entity_archetype,
            );

            return new_entity_ptr;
        }

        pub fn destroyEntity(self: *Self, entity_ptr: EntityPointer) void {
            std.debug.assert(self.entityIsValid(entity_ptr));
            self.destroyed_entitys.append(self.allocator, entity_ptr) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destroyed_entitys.items) |entity_ptr| {
                const entity_archetype = (self.entity_to_archetype_map.get(entity_ptr.entity) orelse unreachable).archetype;

                inline for (0..self.archetypes.len) |i| {
                    const comptime_archetype: ArchetypeType = .make(@intCast(i));
                    if (comptime_archetype == entity_archetype) {
                        self.archetype(comptime_archetype).remove(entity_ptr, self.allocator) catch unreachable;
                    }
                }

                std.debug.assert(self.entity_to_archetype_map.remove(entity_ptr.entity));

                self.unused_entitys.append(self.allocator, entity_ptr) catch unreachable;
            }

            self.destroyed_entitys.clearAndFree(self.allocator);
        }

        /// Takes in a tag or a component and checks if the entity has it.
        pub fn entityHas(
            self: *Self,
            entity_ptr: EntityPointer,
            comptime @"type": type,
        ) bool {
            std.debug.assert(self.entityIsValid(entity_ptr));

            const archetype_type: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;
            const type_id: usize = comptime if (@sizeOf(@"type") != 0) ResourceRegistry.Components.getId(@"type") else ResourceRegistry.Tags.getId(@"type");

            inline for (self.archetypes, 0..) |arc, i| {
                if (ArchetypeType.make(@intCast(i)) == archetype_type) {
                    if (comptime @sizeOf(@"type") != 0) {
                        return @TypeOf(arc).Components.bitset.isSet(type_id);
                    } else {
                        return @TypeOf(arc).Tags.bitset.isSet(type_id);
                    }
                }
            }

            unreachable; // NOTE: Would mean that entity exists in an archetype that isn't in archetypes.
        }

        pub fn getEntityComponent(
            self: *Self,
            entity_ptr: EntityPointer,
            comptime component: type,
        ) !*component {
            std.debug.assert(self.entityIsValid(entity_ptr));
            const entity_archetype: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;

            inline for (self.archetypes, 0..) |arc, i| {
                if (ArchetypeType.make(@intCast(i)) == entity_archetype) {
                    if (comptime @TypeOf(arc).Components.has(component)) {
                        const columnIndex = comptime @TypeOf(arc).Components.index(component);

                        return &arc.tuple_array_list.tuple_of_many_ptrs[columnIndex][arc.entity_to_row_map.get(entity_ptr.entity).?.value()];
                    }
                    return error.ComponentNotFound;
                }
            }

            return error.ComponentNotFound;
        }

        /// This will transfer entity from one archetype to another, but this will require an existing component.
        pub fn addComponentToEntity(self: *Self, entity_ptr: EntityPointer, component: anytype) !void {
            const T = @TypeOf(component);

            std.debug.assert(self.entityIsValid(entity_ptr));

            const old_entity_archetype: ArchetypeType = (self.entity_to_archetype_map.get(entity_ptr.entity) orelse unreachable).archetype;
            const component_bitset: ResourceRegistry.Components.Bitset = comptime ResourceRegistry.Components.getBitset(&.{T});

            inline for (0..self.archetypes.len) |i| {
                const comptime_archetype = ArchetypeType.make(@intCast(i));

                if (comptime_archetype == old_entity_archetype) {
                    if (comptime TypeOfArchetype(comptime_archetype).Components.bitset.isSet(ResourceRegistry.Components.getId(T))) return error.EntityHasComponent;

                    const new_component_bitset = comptime TypeOfArchetype(comptime_archetype).Components.bitset.unionWith(component_bitset);
                    const new_entity_archetype: ArchetypeType = try comptime ResourceRegistry.Archetypes.getIndexByBitsets(new_component_bitset, TypeOfArchetype(comptime_archetype).Tags.bitset);

                    const components = init: {
                        const old_components = self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable;
                        var components: ct.TupleOfItems(&TypeOfArchetype(new_entity_archetype).Components.types) = undefined;

                        inline for (TypeOfArchetype(comptime_archetype).Components.types, 0..) |comp, j| {
                            components[comptime TypeOfArchetype(new_entity_archetype).Components.index(comp)] = old_components[j];
                        }

                        components[comptime TypeOfArchetype(new_entity_archetype).Components.index(T)] = component;

                        break :init components;
                    };

                    self.setEntity(entity_ptr, components, new_entity_archetype);

                    return;
                }
            }

            unreachable;
        }

        pub fn addTagToEntity(self: *Self, entity_ptr: EntityPointer, comptime tag: type) !void {
            std.debug.assert(self.entityIsValid(entity_ptr));

            const old_archetype: ArchetypeType = (self.entity_to_archetype_map.get(entity_ptr.entity) orelse unreachable).archetype;
            const tag_bitset: ResourceRegistry.Tags.Bitset = comptime ResourceRegistry.Tags.getBitset(&.{tag});

            inline for (0..self.archetypes.len) |i| {
                const comptime_archetype = ArchetypeType.make(@intCast(i));

                if (comptime_archetype == old_archetype) {
                    if (comptime TypeOfArchetype(comptime_archetype).Tags.bitset.isSet(ResourceRegistry.Tags.getId(tag))) return error.EntityHasTag;

                    const new_tag_bitset = comptime TypeOfArchetype(comptime_archetype).Tags.bitset.unionWith(tag_bitset);
                    const new_archetype = try comptime ResourceRegistry.Archetypes.getIndexByBitsets(TypeOfArchetype(comptime_archetype).Components.bitset, new_tag_bitset);

                    self.setEntity(
                        entity_ptr,
                        if (comptime TypeOfArchetype(new_archetype).Components.orderEql(&TypeOfArchetype(comptime_archetype).Components.types))
                            self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable
                        else
                            translateTupleToTuple(
                                TypeOfArchetype(comptime_archetype).Components.type,
                                self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable,
                                TypeOfArchetype(new_archetype).Components.type,
                            ),
                        new_archetype,
                    );

                    return;
                }
            }

            unreachable;
        }

        pub fn removeFromEntity(self: *Self, entity_ptr: EntityPointer, comptime T: type) !void {
            std.debug.assert(self.entityIsValid(entity_ptr));
            const old_entity_archetype: ArchetypeType = (self.entity_to_archetype_map.get(entity_ptr.entity) orelse unreachable).archetype;

            const is_component: bool = @sizeOf(T) != 0;
            const id: usize = comptime if (@sizeOf(T) != 0) ResourceRegistry.Components.getId(T) else ResourceRegistry.Tags.getId(T);

            inline for (0..self.archetypes.len) |i| {
                const comptime_archetype = ArchetypeType.make(@intCast(i));

                if (comptime_archetype == old_entity_archetype) {
                    if (is_component) {
                        if (comptime !TypeOfArchetype(comptime_archetype).Components.bitset.isSet(id)) return error.EntityIsMissingComponent;
                    } else {
                        if (comptime !TypeOfArchetype(comptime_archetype).Tags.bitset.isSet(id)) return error.EntityIsMissingTag;
                    }

                    const new_component_bitset, const new_tag_bitset = comptime init: {
                        if (is_component) {
                            var new_component_bitset = TypeOfArchetype(comptime_archetype).Components.bitset;
                            new_component_bitset.unset(id);
                            break :init .{ new_component_bitset, TypeOfArchetype(comptime_archetype).Tags.bitset };
                        } else {
                            var new_tag_bitset = TypeOfArchetype(comptime_archetype).Tags.bitset;
                            new_tag_bitset.unset(id);

                            break :init .{ TypeOfArchetype(comptime_archetype).Components.bitset, new_tag_bitset };
                        }
                    };

                    const new_entity_archetype = try comptime ResourceRegistry.Archetypes.getIndexByBitsets(new_component_bitset, new_tag_bitset);

                    var iterator = self.singleton_to_entity_map.iterator();
                    while (iterator.next()) |entry| {
                        if (is_component) {
                            if (entry.value_ptr.entity == entity_ptr.entity and self.singletons.items[entry.key_ptr.value()][0].isSet(id)) {
                                self.clearSingletonsEntity(entry.key_ptr.*);
                            }
                        } else {
                            if (entry.value_ptr.entity == entity_ptr.entity and self.singleton(entry.key_ptr.*)[1].isSet(id)) {
                                self.clearSingletonsEntity(entry.key_ptr.*);
                            }
                        }
                    }

                    self.setEntity(entity_ptr, init: {
                        if (is_component) {
                            const old_components = self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable;
                            var components: ct.TupleOfItems(&TypeOfArchetype(new_entity_archetype).Components.types) = undefined;

                            inline for (TypeOfArchetype(new_entity_archetype).Components.types, 0..) |component, j| {
                                components[j] = old_components[comptime TypeOfArchetype(comptime_archetype).Components.index(component)];
                            }

                            break :init components;
                        } else {
                            if (comptime TypeOfArchetype(comptime_archetype).Components.orderEql(&TypeOfArchetype(new_entity_archetype).Components.types))
                                break :init self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable
                            else
                                break :init translateTupleToTuple(
                                    TypeOfArchetype(comptime_archetype).Components.type,
                                    self.archetype(comptime_archetype).popRemove(entity_ptr, self.allocator) catch unreachable,
                                    TypeOfArchetype(new_entity_archetype).Components.type,
                                );
                        }
                    }, new_entity_archetype);

                    return;
                }
            }

            unreachable;
        }

        fn getMeantArchetypeTemplate(template: Template) Template {
            for (templates) |temp| {
                if (temp.eql(template)) return temp;
            }

            @compileError("Supplied template didn't have a corresponding archetype.");
        }

        pub fn getArchetype(self: *Self, comptime template: Template) @TypeOf(self.archetype(comptime ResourceRegistry.Archetypes.getIndexByTemplate(template) catch
            @compileError("No matching archetype with the given template."))) {
            return self.archetype(comptime ResourceRegistry.Archetypes.getIndexByTemplate(template) catch @compileError("No matching archetype with the given template."));
        }

        pub fn Iterator(filter: Filter) type {
            @setEvalBranchQuota(10_000); // FIXME: I don't know how we hit 1000 so easily this is a bad fix.
            return GenericIterator(
                filter.component,
                ResourceRegistry.Archetypes.matchingIndexCount(
                    &.{filter.component},
                    filter.tags,
                    filter.exclude.components,
                    filter.exclude.tags,
                ),
            );
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getIterator(self: *Self, filter: Filter) ?Iterator(filter) {
            const matching_archetypes = comptime ResourceRegistry.Archetypes.matchingIndices(
                &.{filter.component},
                filter.tags,
                filter.exclude.components,
                filter.exclude.tags,
            );

            var component_arrays: [matching_archetypes.len][]filter.component = undefined;
            var entitys: [matching_archetypes.len][]EntityPointer = undefined;
            var buffer_len: usize = 0;

            inline for (matching_archetypes) |archetype_type| {
                if (self.archetype(archetype_type).tuple_array_list.count > 0) {
                    component_arrays[buffer_len] = self.archetype(archetype_type).tuple_array_list.getItemArray(filter.component);
                    entitys[buffer_len] = self.archetype(archetype_type).entitys.items;
                    buffer_len += 1;
                }
            }

            if (buffer_len == 0) {
                return null;
            }

            return .init(component_arrays, entitys, @intCast(buffer_len));
        }

        pub fn TupleIterator(filter: TupleFilter) type {
            @setEvalBranchQuota(10_000); // FIXME: I don't know how we hit 1000 so easily this is a bad fix.
            return GenericTupleIterator(
                filter.include.components,
                ResourceRegistry.Archetypes.matchingIndexCount(
                    filter.include.components,
                    filter.include.tags,
                    filter.exclude.components,
                    filter.exclude.tags,
                ),
            );
        }

        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getTupleIterator(self: *Self, comptime filter: TupleFilter) ?TupleIterator(filter) {
            const matching_archetypes = comptime ResourceRegistry.Archetypes.matchingIndices(
                filter.include.components,
                filter.include.tags,
                filter.exclude.components,
                filter.exclude.tags,
            );

            var tuple_of_buffers: TupleOfBuffers(filter.include.components, matching_archetypes.len) = undefined;
            var entitys: [matching_archetypes.len][]EntityPointer = undefined;
            var buffer_len: usize = 0;

            inline for (matching_archetypes) |archetype_type| {
                if (self.archetype(archetype_type).tuple_array_list.count > 0) {
                    entitys[buffer_len] = self.archetype(archetype_type).entitys.items;
                    inline for (filter.include.components, 0..) |component, j| {
                        tuple_of_buffers[j][buffer_len] = self.archetype(archetype_type).tuple_array_list.getItemArray(component);
                    }

                    buffer_len += 1;
                }
            }

            if (buffer_len == 0) {
                return null;
            }

            return GenericTupleIterator(filter.include.components, matching_archetypes.len).init(tuple_of_buffers, entitys, @intCast(buffer_len));
        }

        pub fn createSingleton(self: *Self, requirements: Template) SingletonType {
            const component_bitset: ResourceRegistry.Components.Bitset = comptime ResourceRegistry.Components.getBitset(requirements.components);
            const tag_bitset: ResourceRegistry.Tags.Bitset = comptime ResourceRegistry.Tags.getBitset(requirements.tags);

            comptime check: {
                for (self.archetypes) |archetype_type| {
                    if (@TypeOf(archetype_type).Components.bitset.intersectWith(component_bitset).eql(component_bitset) and
                        @TypeOf(archetype_type).Tags.bitset.intersectWith(tag_bitset).eql(tag_bitset))
                    {
                        break :check;
                    }
                }

                @compileError("No matching archetype");
            }

            self.singletons.append(self.allocator, .{ component_bitset, tag_bitset }) catch unreachable;
            return SingletonType.make(@intCast(self.singletons.items.len - 1));
        }

        pub fn setSingletonsEntity(self: *Self, singleton_type: SingletonType, entity_ptr: EntityPointer) !void {
            std.debug.assert(self.entityIsValid(entity_ptr));
            std.debug.assert(singleton_type.value() < self.singletons.items.len);

            const component_bitset, const tag_bitset = self.singleton(singleton_type);
            const archetype_type: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;

            inline for (0..self.archetypes.len) |i| {
                const comptime_archetype = ArchetypeType.make(@intCast(i));

                if (comptime_archetype == archetype_type) {
                    if (TypeOfArchetype(comptime_archetype).Components.bitset.intersectWith(component_bitset).eql(component_bitset) and
                        TypeOfArchetype(comptime_archetype).Tags.bitset.intersectWith(tag_bitset).eql(tag_bitset))
                    {
                        self.singleton_to_entity_map.put(self.allocator, singleton_type, entity_ptr) catch unreachable;
                        return;
                    } else {
                        return error.EntityNotMatchRequirments;
                    }
                }
            }

            unreachable;
        }

        pub fn clearSingletonsEntity(self: *Self, singleton_type: SingletonType) void {
            _ = self.singleton_to_entity_map.remove(singleton_type);
        }

        pub fn getSingletonsEntity(self: *Self, singleton_type: SingletonType) ?EntityPointer {
            std.debug.assert(singleton_type.value() < self.singletons.items.len);

            if (self.singleton_to_entity_map.get(singleton_type)) |entity| {
                if (self.entity_to_archetype_map.get(entity.entity)) |_| {
                    return entity;
                }

                std.debug.assert(self.singleton_to_entity_map.remove(singleton_type));
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
        var expected = EcsType.ResourceRegistry.Components.Bitset.initEmpty();
        expected.set(0);
        const component_bitset = comptime EcsType.ResourceRegistry.Components.getBitset(&.{Position});
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.ResourceRegistry.Components.Bitset.initEmpty();
        expected.set(0);
        expected.set(1);
        const component_bitset = comptime EcsType.ResourceRegistry.Components.getBitset(&.{ Position, Collider });
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.ResourceRegistry.Components.Bitset.initEmpty();
        expected.set(1);
        const component_bitset = comptime EcsType.ResourceRegistry.Components.getBitset(&.{Collider});
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = EcsType.ResourceRegistry.Tags.Bitset.initEmpty();
        expected.set(0);
        const tag_bitset = comptime EcsType.ResourceRegistry.Tags.getBitset(&.{Tag});
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
            .{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } },
            &.{Tag},
        );
        _ = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{},
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

    const entity1 = ecs.createEntity(.{Position{ .x = 1, .y = 1 }}, &.{});
    const entity2 = ecs.createEntity(.{Position{ .x = 1, .y = 1 }}, &.{Tag});
    const entity3 = ecs.createEntity(.{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } }, &.{Tag});

    const entity1_archetype_index = ecs.entity_to_archetype_map.get(entity1.entity).?.archetype.value();
    const entity2_archetype_index = ecs.entity_to_archetype_map.get(entity2.entity).?.archetype.value();
    const entity3_archetype_index = ecs.entity_to_archetype_map.get(entity3.entity).?.archetype.value();

    try std.testing.expect(entity1_archetype_index != entity2_archetype_index);
    try std.testing.expect(entity1_archetype_index != entity3_archetype_index);
    try std.testing.expect(entity2_archetype_index != entity3_archetype_index);
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
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 1, .y = 1 } },
            &.{Tag},
        );

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try ecs.removeFromEntity(entity, Collider);
        }

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(!ecs.entityHas(entity, Collider));
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
            .{Position{ .x = 1, .y = 1 }},
            &.{Tag},
        );

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try ecs.addComponentToEntity(entity, Collider{ .x = 1, .y = 0 });
        }

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHas(entity, Collider));
            const collider = try ecs.getEntityComponent(entity, Collider);
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
        .{ .components = &.{Position}, .tags = &.{} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{},
        );

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try std.testing.expect(!ecs.entityHas(entity, Tag));
            try ecs.addTagToEntity(entity, Tag);
        }

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHas(entity, Tag));
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
        .{ .components = &.{Position}, .tags = &.{} },
    }) = .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{Tag},
        );

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            try std.testing.expect(ecs.entityHas(entity, Tag));
            try ecs.removeFromEntity(entity, Tag);
        }

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);

            try std.testing.expect(!ecs.entityHas(entity, Tag));
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
            .{Position{ .x = 1, .y = 1 }},
            &.{},
        );

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 1, .y = 1 }, position.*);
            position.x = 2;
        }

        {
            const position = try ecs.getEntityComponent(entity, Position);
            try std.testing.expectEqual(Position{ .x = 2, .y = 1 }, position.*);
        }
    }

    _ = ecs.createEntity(.{ Collider{ .x = 5, .y = 5 }, Position{ .x = 4, .y = 4 } }, &.{Tag});
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

    const entity_ptr = ecs.createEntity(
        .{Position{ .x = 1, .y = 1 }},
        &.{},
    );

    try std.testing.expect(ecs.entityIsValid(entity_ptr) == true);

    ecs.destroyEntity(entity_ptr);

    ecs.clearDestroyedEntitys();
    try std.testing.expect(ecs.destroyed_entitys.items.len == 0);
    try std.testing.expect(ecs.unused_entitys.items.len == 1);

    try std.testing.expect(ecs.entityIsValid(entity_ptr) == false);

    const entity_ptr2 = ecs.createEntity(
        .{Position{ .x = 1, .y = 1 }},
        &.{},
    );

    try std.testing.expect(ecs.entityIsValid(entity_ptr2) == true);

    try std.testing.expect(entity_ptr.entity.value() == entity_ptr2.entity.value());
    try std.testing.expect(entity_ptr.generation.value() == entity_ptr2.generation.value() - 1);
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
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
            &.{Tag},
        );
        _ = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{},
        );
        _ = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{Tag},
        );
    }

    var iterator = ecs.getIterator(.{ .component = Position }).?;

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

    var iterator2 = ecs.getIterator(.{ .component = Position, .exclude = .{ .tags = &.{Tag} } }).?;

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
            .{ Position{ .x = 1, .y = 1 }, Collider{ .x = 5, .y = 5 } },
            &.{Tag},
        );
    }

    {
        var iterator = ecs.getIterator(.{ .component = Position }).?;

        var i: u32 = 0;
        while (iterator.next()) |_| {
            try std.testing.expect(iterator.getCurrentEntity().entity.value() == i);
            i += 1;
        }
    }

    {
        ecs.destroyEntity(.{ .entity = .make(0), .generation = .make(0) });
        ecs.clearDestroyedEntitys();

        var iterator = ecs.getIterator(.{ .component = Position }).?;

        if (iterator.next()) |_| {
            try std.testing.expect(iterator.current_entity.entity.value() == 99);
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
            .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
            &.{Tag},
        );
        _ = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{},
        );
        _ = ecs.createEntity(
            .{Position{ .x = 1, .y = 1 }},
            &.{Tag},
        );
    }

    var iterator = ecs.getTupleIterator(.{ .include = .{ .components = &.{ Position, Collider } } }).?;

    try std.testing.expect(iterator.tuple_of_buffers[0].len == 1);
    try std.testing.expect(iterator.tuple_of_buffers[0][0].len == 100);

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 6);
        try std.testing.expect(components[0].y == 5);
        components[0].x = 7;
        components[0].y = 7;
    }

    var iterator2 = ecs.getTupleIterator(.{ .include = .{ .components = &.{ Position, Collider } } }).?;

    while (iterator2.next()) |components| {
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
        .{ Position{ .x = 6, .y = 5 }, Collider{ .x = 5, .y = 5 } },
        &.{Tag},
    );

    const entity2 = ecs.createEntity(
        .{Position{ .x = 1, .y = 1 }},
        &.{},
    );

    const entity3 = ecs.createEntity(
        .{Position{ .x = 1, .y = 1 }},
        &.{Tag},
    );

    {
        const singleton = ecs.createSingleton(.{ .components = &.{Position}, .tags = &.{Tag} });
        try std.testing.expect(ecs.getSingletonsEntity(singleton) == null);

        ecs.setSingletonsEntity(singleton, entity1) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        testScope: { // NOTE: Should fail, required tag missing!
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
