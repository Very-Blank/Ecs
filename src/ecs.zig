const std = @import("std");
const help = @import("help.zig");

const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const GenericIterator = @import("iterator.zig").GenericIterator;
const GenericTupleIterator = @import("tupleIterator.zig").GenericTupleIterator;
const TupleOfBuffers = help.TupleOfBuffers;

const Template = @import("Template.zig");
const TupleFilter = @import("TupleFilter.zig");
const Filter = @import("Filter.zig");

const Registry = @import("registery.zig").Registry;
const LinkTable = @import("links.zig").LinkTable;
const IndexMode = @import("links.zig").IndexMode;

pub fn itoa(comptime value: anytype) [:0]const u8 {
    comptime var string: [:0]const u8 = "";
    comptime var num = value;

    if (num == 0) {
        string = string ++ .{'0'};
    } else {
        while (num != 0) {
            string = .{'0' + (num % 10)} ++ string;
            num = num / 10;
        }
    }

    return string;
}

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

    pub inline fn eql(self: EntityPointer, other: EntityPointer) bool {
        return self.entity == other.entity and self.generation == other.generation;
    }
};

pub const ArchetypePointer = struct {
    archetype: ArchetypeType,
    generation: GenerationType,
};

pub fn Ecs(
    comptime templates: []const Template,
    comptime _: []const struct { name: []const u8, T: type, mode: IndexMode, requirments: Template },
) type {
    if (templates.len == 0) {
        @compileError("Was called with an empty template array.");
    }

    for (templates, 0..) |template, i| {
        for (i + 1..templates.len) |j| {
            if (template.eql(templates[j])) @compileError("Two templates where the same which is not allowed. Template one index: " ++ itoa(i) ++ ", template two index: " ++ itoa(j));
        }
    }

    for (templates, 0..) |template, i| {
        if (template.components.len == 0) @compileError("Template components was empty, which is not allowed. Template index: " ++ itoa(i) ++ ".");

        for (0..template.components.len) |cur_component_index| {
            if (@sizeOf(template.components[cur_component_index]) == 0)
                @compileError("Templates component was a ZST, which is not allowed. Template index: " ++ itoa(cur_component_index) ++ ", component: " ++ @typeName(template.components[cur_component_index]));

            for (cur_component_index + 1..template.components.len) |nex_component_index| {
                if (template.components[cur_component_index] == template.components[nex_component_index])
                    @compileError("Template had two of the same component. Template index: " ++ itoa(i) ++ ", component: " ++ @typeName(template.components[cur_component_index]));
            }
        }

        for (0..template.tags.len) |cur_tag_index| {
            if (@sizeOf(template.tags[cur_tag_index]) != 0)
                @compileError("Templates tag wasn't a ZST, which is not allowed. Template index: " ++ itoa(cur_tag_index) ++ ", tag: " ++ @typeName(template.tags[cur_tag_index]));

            for (cur_tag_index + 1..template.tags.len) |nex_tag_index| {
                if (template.tags[cur_tag_index] == template.tags[nex_tag_index])
                    @compileError("Template had two of the same tag. Template index: " ++ itoa(i) ++ ", tag: " ++ @typeName(template.tags[cur_tag_index]));
            }
        }
    }

    return struct {
        pub const Archetype = @import("archetype.zig").Archetype(Components.types.len, Tags.types.len);

        pub const Singleton = struct { Components.Bitset, Tags.Bitset };

        pub const Components = Registry(templates, "components");

        pub const Tags = Registry(templates, "tags");

        pub const Archetypes = struct {
            pub fn getByBitset(component_bitset: Components.Bitset, tag_bitset: Tags.Bitset) !ArchetypeType {
                for (templates, 0..) |template, i| {
                    if (Components.bitset(template.components) == component_bitset and tag_bitset == Tags.bitset(template.components)) return .make(i);
                }

                return error.ArchetypeDoesNotExist;
            }

            pub fn getByTemplate(other: Template) !ArchetypeType {
                for (templates, 0..) |template, i| {
                    if (template.eql(other)) return .make(i);
                }

                return error.ArchetypeDoesNotExist;
            }

            pub fn matchingCount(
                include_components: []const type,
                include_tags: []const type,
                exclude_components: []const type,
                exclude_tags: []const type,
            ) usize {
                const component_bitset: Components.Bitset = Components.bitset(include_components);
                const tag_bitset: Tags.Bitset = Tags.bitset(include_tags);

                const exclude_component_bitset: Components.Bitset = Components.bitset(exclude_components);
                const exclude_tag_bitset: Tags.Bitset = Tags.bitset(exclude_tags);

                var matching_archetype_count: usize = 0;

                for (templates) |template| {
                    const archetype_component_bitset = Components.bitset(template.components);
                    const archetype_tag_bitset = Tags.bitset(template.tags);

                    if (archetype_component_bitset.intersectWith(component_bitset).eql(component_bitset) and
                        archetype_tag_bitset.intersectWith(tag_bitset).eql(tag_bitset) and
                        archetype_component_bitset.intersectWith(exclude_component_bitset).eql(.empty) and
                        archetype_tag_bitset.intersectWith(exclude_tag_bitset).eql(.empty))
                    {
                        matching_archetype_count += 1;
                    }
                }

                return matching_archetype_count;
            }

            pub fn getMatching(
                include_components: []const type,
                include_tags: []const type,
                exclude_components: []const type,
                exclude_tags: []const type,
            ) [matchingCount(include_components, include_tags, exclude_components, exclude_tags)]ArchetypeType {
                const component_bitset: Components.Bitset = Components.bitset(include_components);
                const tag_bitset: Tags.Bitset = Tags.bitset(include_tags);

                const exclude_component_bitset: Components.Bitset = Components.bitset(exclude_components);
                const exclude_tag_bitset: Tags.Bitset = Tags.bitset(exclude_tags);

                const matching_archetype_count: usize = matchingCount(include_components, include_tags, exclude_components, exclude_tags);
                if (matching_archetype_count == 0) @compileError("No matching archetypes with the supplied include and exclude.");

                var archetype_indices: [matching_archetype_count]ArchetypeType = undefined;

                var current_index = 0;
                for (templates, 0..) |template, i| {
                    const archetype_component_bitset = Components.bitset(template.components);
                    const archetype_tag_bitset = Tags.bitset(template.tags);

                    if (archetype_component_bitset.supersetOf(component_bitset) and
                        archetype_tag_bitset.supersetOf(tag_bitset) and
                        archetype_component_bitset.intersectWith(exclude_component_bitset).eql(.empty) and
                        archetype_tag_bitset.intersectWith(exclude_tag_bitset).eql(.empty))
                    {
                        archetype_indices[current_index] = .make(i);
                        current_index += 1;
                    }
                }

                return archetype_indices;
            }
        };

        ptr: *anyopaque,

        const Self = @This();

        pub fn init(capacities: [templates.len]u32, _: std.mem.Allocator) !Self {
            var component_counts: [Components.types.len]u32 = undefined;
            var entity_capacity: u32 = 0;
            inline for (templates, 0..) |template, i| {
                entity_capacity += capacities[i];
                inline for (template.components) |component| {
                    component_counts[comptime Components.id(component)] = capacities[i];
                }
            }

            @compileError("TODO");
        }

        pub fn initFromSlice(_: []const u8, _: std.mem.Allocator) !Self {
            @compileError("TODO");
        }

        pub fn deinit(_: *Self, _: std.mem.Allocator) void {
            @compileError("TODO");
        }

        // These are here so you don't accidently use the wrong type of enum type to access any of these. LIKE I DID!
        inline fn archetype(_: *Self, _: ArchetypeType) *Archetype {
            // std.debug.assert(archetype_type.value() < self.archetypes.len);
            @compileError("TODO");
        }

        inline fn singleton(_: *Self, _: SingletonType) Singleton {
            // std.debug.assert(singleton_type.value() < self.singletons.items.len);
            @compileError("TODO");
        }

        pub inline fn entityIsValid(_: *const Self, _: EntityPointer) bool {
            @compileError("TODO");
        }

        /// Creates an entity with the spesified components and tags, adding the components to the correct archetype.
        /// If any iterators include the archetype in it's buffer's, using those iterators is undefiend behaviour.
        pub fn createEntity(_: *Self, _: anytype, comptime _: []const type) EntityPointer {
            @compileError("TODO");
            // const template: Template = .{ .components = &comptime help.typesFromTuple(@TypeOf(components)), .tags = tags };
            // const entity_archetype: ArchetypeType = comptime Archetypes.getByTemplate(template) catch @compileError("Archetype matching required components and tags didn't exist.");

            // const new_entity_ptr: EntityPointer = init: {
            //     if (self.unused_entitys.items.len > 0) {
            //         const entity_ptr = self.unused_entitys.pop().?;
            //         break :init .{ .entity = entity_ptr.entity, .generation = GenerationType.make(entity_ptr.generation.value() + 1) };
            //     }
            //
            //     self.entity_count += 1;
            //     break :init .{ .entity = EntityType.make(self.entity_count - 1), .generation = GenerationType.make(0) };
            // };

            // self.setEntity(
            //     templates[entity_archetype.value()].components,
            //     new_entity_ptr,
            //     if (comptime templates[entity_archetype.value()].orderEql(template, "components"))
            //         components
            //     else
            //         help.translateTuples(template.components, components, templates[entity_archetype.value()].components),
            //     entity_archetype,
            // );
            //
            // return new_entity_ptr;
        }

        /// Marks the entity to be removed in the next clearDestroyedEntitys call.
        pub fn destroyEntity(_: *Self, _: EntityPointer) void {
            @compileError("TODO");
        }

        /// Destroyes all entitys that where marked by destroyEntity.
        /// If any iterators include any of the destroyed entitys, using those iterators is undefiend behaviour.
        pub fn clearDestroyedEntitys(_: *Self) void {
            @compileError("TODO");
        }

        /// Takes in a tag or a component and checks if the entity has it.
        pub inline fn entityHas(
            _: *Self,
            _: EntityPointer,
            comptime _: type,
        ) bool {
            // std.debug.assert(self.entityIsValid(entity_ptr));
            //
            // if (@sizeOf(T) != 0) {
            //     return self.archetype(self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype).component_bitset.isSet(comptime Components.id(T));
            // }
            //
            // return self.archetype(self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype).tag_bitset.isSet(comptime Tags.id(T));
        }

        pub fn getEntityComponent(
            _: *Self,
            _: EntityPointer,
            comptime component: type,
        ) ?*component {
            @compileError("TODO");
        }

        pub fn getEntityComponents(
            _: *Self,
            _: EntityPointer,
            comptime components: []const type,
        ) ?help.TupleOfItemPtrs(components) {
            // comptime for (components) |component|
            //     if (@sizeOf(component) == 0) @compileError("Unexpected tag " ++ @typeName(component) ++ ", expected a component.");
            //
            // std.debug.assert(self.entityIsValid(entity_ptr));
            //
            // const component_bitset: Components.Bitset = comptime Components.bitset(components);
            //
            // const entity_archetype: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;
            //
            // if (self.archetype(entity_archetype).component_bitset.supersetOf(component_bitset)) {
            //     const row = self.archetype(entity_archetype).getEntityRowIndex(entity_ptr);
            //     var tuple: help.TupleOfItemPtrs(components) = undefined;
            //
            //     inline for (components, 0..) |component, i| {
            //         const id = comptime Components.id(component);
            //         tuple[i] = &self.archetype(entity_archetype).getItemArray(component, id)[row];
            //     }
            //
            //     return tuple;
            // }
            //
            // return null;
        }

        /// This will transfer entity from one archetype to another while adding a component.
        pub fn addComponentToEntity(_: *Self, _: EntityPointer, _: anytype) !void {
            @compileError("TODO");
        }

        /// This will transfer entity from one archetype to another while adding a tag.
        pub fn addTagToEntity(_: *Self, _: EntityPointer, comptime _: type) !void {
            @compileError("TODO");
        }

        /// This will transfer entity from one archetype to another without the specified component or tag.
        pub fn removeFromEntity(_: *Self, _: EntityPointer, comptime _: type) !void {
            @compileError("TODO");
        }

        /// The unique iterator type for this ecs.
        /// Unique because the iterator depends on the amount of matches.
        pub fn Iterator(filter: Filter) type {
            @setEvalBranchQuota(10_000); // FIXME: I don't know how we hit 1000 so easily this is a bad fix.
            return GenericIterator(
                filter.component,
                Archetypes.matchingCount(
                    &.{filter.component},
                    filter.tags,
                    filter.exclude.components,
                    filter.exclude.tags,
                ),
            );
        }

        /// Gets an iterator specified by the filter.
        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getIterator(_: *Self, filter: Filter) ?Iterator(filter) {
            @compileError("TODO");
            // const matching_archetypes = comptime Archetypes.getMatching(
            //     &.{filter.component},
            //     filter.tags,
            //     filter.exclude.components,
            //     filter.exclude.tags,
            // );
            //
            // var component_arrays: [matching_archetypes.len][]filter.component = undefined;
            // var entitys: [matching_archetypes.len][]EntityPointer = undefined;
            // var buffer_len: usize = 0;
            //
            // for (matching_archetypes) |archetype_type| {
            //     if (self.archetype(archetype_type).tuple_array_list.count > 0) {
            //         component_arrays[buffer_len] = self.archetype(archetype_type).getItemArray(filter.component, comptime Components.id(filter.component));
            //         entitys[buffer_len] = self.archetype(archetype_type).row_to_entity_map.values();
            //         buffer_len += 1;
            //     }
            // }
            //
            // if (buffer_len == 0) {
            //     return null;
            // }
            //
            // return .init(component_arrays, entitys, @intCast(buffer_len));
        }

        /// The unique tuple iterator type for this ecs.
        /// Unique because the tuple iterator depends on the amount of matches.
        pub fn TupleIterator(filter: TupleFilter) type {
            @setEvalBranchQuota(10_000); // FIXME: I don't know how we hit 1000 so easily this is a bad fix.
            return GenericTupleIterator(
                filter.include.components,
                Archetypes.matchingCount(
                    filter.include.components,
                    filter.include.tags,
                    filter.exclude.components,
                    filter.exclude.tags,
                ),
            );
        }

        /// Gets a tuple iterator specified by the tuple filter.
        /// Destroying or adding entity will possibly make iterator's pointers undefined.
        pub fn getTupleIterator(_: *Self, comptime filter: TupleFilter) ?TupleIterator(filter) {
            @compileError("TODO");
            // const matching_archetypes = comptime Archetypes.getMatching(
            //     filter.include.components,
            //     filter.include.tags,
            //     filter.exclude.components,
            //     filter.exclude.tags,
            // );
            //
            // var tuple_of_buffers: TupleOfBuffers(filter.include.components, matching_archetypes.len) = undefined;
            // var entitys: [matching_archetypes.len][]EntityPointer = undefined;
            // var buffer_len: usize = 0;
            //
            // for (matching_archetypes) |archetype_type| {
            //     if (self.archetype(archetype_type).tuple_array_list.count > 0) {
            //         entitys[buffer_len] = self.archetype(archetype_type).row_to_entity_map.values();
            //
            //         inline for (filter.include.components, 0..) |component, j| {
            //             tuple_of_buffers[j][buffer_len] = self.archetype(archetype_type).getItemArray(component, comptime Components.id(component));
            //         }
            //
            //         buffer_len += 1;
            //     }
            // }
            //
            // if (buffer_len == 0) {
            //     return null;
            // }
            //
            // return GenericTupleIterator(filter.include.components, matching_archetypes.len).init(tuple_of_buffers, entitys, @intCast(buffer_len));
        }

        /// Creates a singleton that has the specified requirments.
        pub fn createSingleton(_: *Self, comptime requirements: Template) SingletonType {
            const component_bitset: Components.Bitset = comptime Components.bitset(requirements.components);
            const tag_bitset: Tags.Bitset = comptime Tags.bitset(requirements.tags);

            comptime check: {
                for (templates) |template| {
                    const archetype_component_bitest = Components.bitset(template.components);
                    const archetype_tags_bitest = Tags.bitset(template.tags);

                    if (archetype_component_bitest.supersetOf(component_bitset) and
                        archetype_tags_bitest.supersetOf(tag_bitset))
                    {
                        break :check;
                    }
                }

                @compileError("No matching archetype.");
            }

            @compileError("TODO");

            // self.singletons.append(self.allocator, .{ component_bitset, tag_bitset }) catch unreachable;
            // return SingletonType.make(@intCast(self.singletons.items.len - 1));
        }

        /// Sets the singleton to point to an entity if the entity matches the singletons requirments.
        /// If the entity's components or tags change and it no longer matches the singletons requirments the entity will be cleared.
        pub fn setSingletonsEntity(_: *Self, _: SingletonType, _: EntityPointer) !void {
            // std.debug.assert(self.entityIsValid(entity_ptr));
            // std.debug.assert(singleton_type.value() < self.singletons.items.len);
            //
            // const component_bitset, const tag_bitset = self.singleton(singleton_type);
            //
            // const archetype_type: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;
            //
            // if (self.archetype(archetype_type).component_bitset.supersetOf(component_bitset) and
            //     self.archetype(archetype_type).tag_bitset.supersetOf(tag_bitset))
            // {
            //     return self.singleton_to_entity_map.put(self.allocator, singleton_type, entity_ptr) catch @panic("OOM");
            // }
            //
            // return error.EntityNotMatchRequirments;
            //
            @compileError("TODO");
        }

        /// Clears the set entity from the singleton.
        pub fn clearSingletonsEntity(_: *Self, _: SingletonType) void {
            @compileError("TODO");
            // std.debug.assert(self.singleton_to_entity_map.remove(singleton_type));
        }

        // FIXME: entity might not be in the archetype anymore!

        /// Gets the entity that is pointed by the singleton.
        pub fn getSingletonsEntity(_: *Self, _: SingletonType) ?EntityPointer {
            @compileError("TODO");
            // std.debug.assert(singleton_type.value() < self.singletons.items.len);
            //
            // if (self.singleton_to_entity_map.get(singleton_type)) |entity| {
            //     if (self.entityIsValid(entity)) {
            //         return entity;
            //     }
            //
            //     std.debug.assert(self.singleton_to_entity_map.remove(singleton_type));
            // }
            //
            // return null;
        }

        pub fn createLink(
            _: *Self,
            comptime _: []const u8,
            _: EntityPointer,
            _: EntityPointer,
            _: anytype,
        ) !void {
            @compileError("TODO");

            // const component_bitset = @field(self.links, name).component_bitset;
            // const tag_bitset = @field(self.links, name).tag_bitset;
            //
            // inline for (.{ source, desination }) |entity| {
            //     const archetype_type: ArchetypeType = self.entity_to_archetype_map.get(entity.entity).?.archetype;
            //
            //     if (!self.archetype(archetype_type).component_bitset.supersetOf(component_bitset) or
            //         !self.archetype(archetype_type).tag_bitset.supersetOf(tag_bitset))
            //     {
            //         return error.EntityNotMatchRequirments;
            //     }
            // }
            //
            // try @field(self.links, name).create(self.allocator, source, desination, value);
        }

        pub fn linksBySource(_: *const Self, comptime _: []const u8, _: EntityType) []const usize {
            @compileError("TODO");
            // @field(self.links, name).linksBySource(src);
        }

        pub fn linksByDestination(_: *const Self, comptime _: []const u8, _: EntityType) []const usize {
            @compileError("TODO");
            // @field(self.links, name).linksByDestination(dst);
        }

        pub fn destroyLink(
            _: *Self,
            comptime _: []const u8,
            _: EntityPointer,
            _: EntityPointer,
        ) !void {
            @compileError("TODO");
            // @field(self.links, name).destroy(self.allocator, @field(self.links, name).linkIndex(source, desination) orelse return error.LinkMissing);
        }

        pub fn destroyLinkByIndex(
            _: *Self,
            comptime _: []const u8,
            _: usize,
        ) !void {
            @compileError("TODO");
            // @field(self.links, name).destroy(self.allocator, index);
        }

        pub fn getLinks(
            _: *Self,
            comptime name: []const u8,
        ) struct {
            sources: []const EntityPointer,
            destinations: []const EntityPointer,
            data: []const @FieldType(@FieldType(Self, "links"), name).InnerType,
        } {
            @compileError("TODO");
            // return .{
            //     .sources = @field(self.links, name).getSources(),
            //     .destinations = @field(self.links, name).getDestinations(),
            //     .data = @field(self.links, name).getData(),
            // };
        }
    };
}

const TestingTypes = struct {
    const Collider = struct {
        x: u32,
        y: u32,
    };

    const Position = struct {
        x: u32,
        y: u32,
    };

    const Tag = struct {};

    const EcsType = Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }, &.{});
};

// NOTE: These test are kind of unnecceary since you would get compiler errors before getting here.
test "Is component or tag arrays correct" {
    // NOTE: Components
    try std.testing.expect(TestingTypes.EcsType.Components.types.len == 2);
    inline for (&.{ TestingTypes.Position, TestingTypes.Collider }, 0..) |@"type", i| {
        try std.testing.expect(comptime @"type" == TestingTypes.EcsType.Components.types[i]);
    }

    inline for (&.{TestingTypes.Tag}, 0..) |@"type", i| {
        try std.testing.expect(comptime @"type" == TestingTypes.EcsType.Tags.types[i]);
    }
}

test "Is component or tag bitsets generated by the ecs are correct" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);
    defer ecs.deinit();

    // NOTE: Components
    {
        var expected = TestingTypes.EcsType.Components.Bitset.initEmpty();
        expected.set(0);
        const component_bitset = comptime TestingTypes.EcsType.Components.bitset(&.{TestingTypes.Position});
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = TestingTypes.EcsType.Components.Bitset.initEmpty();
        expected.set(0);
        expected.set(1);
        const component_bitset = comptime TestingTypes.EcsType.Components.bitset(&.{ TestingTypes.Position, TestingTypes.Collider });
        try std.testing.expect(expected.eql(component_bitset));
    }

    {
        var expected = TestingTypes.EcsType.Components.Bitset.initEmpty();
        expected.set(1);
        const component_bitset = comptime TestingTypes.EcsType.Components.bitset(&.{TestingTypes.Collider});
        try std.testing.expect(expected.eql(component_bitset));
    }

    // NOTE: Tags
    {
        var expected = TestingTypes.EcsType.Tags.Bitset.initEmpty();
        expected.set(0);
        const tag_bitset = comptime TestingTypes.EcsType.Tags.bitset(&.{TestingTypes.Tag});
        try std.testing.expect(expected.eql(tag_bitset));
    }
}

test "Creating a new entity" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    ecs.setArchetypeInitCapcacity(.{ .components = &.{ TestingTypes.Position, TestingTypes.Collider }, .tags = &.{TestingTypes.Tag} }, 100);
    ecs.setArchetypeInitCapcacity(.{ .components = &.{TestingTypes.Position}, .tags = &.{} }, 100);

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ TestingTypes.Collider{ .x = 5, .y = 5 }, TestingTypes.Position{ .x = 4, .y = 4 } },
            &.{TestingTypes.Tag},
        );
        _ = ecs.createEntity(
            .{TestingTypes.Position{ .x = 1, .y = 1 }},
            &.{},
        );
    }
}

test "Getting a single component that an entity owns." {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    {
        const entity = ecs.createEntity(
            .{ TestingTypes.Position{ .x = 1, .y = 1 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        );

        {
            const position = ecs.getEntityComponent(entity, TestingTypes.Position).?;
            try std.testing.expectEqual(TestingTypes.Position{ .x = 1, .y = 1 }, position.*);
            position.x = 2;
        }

        {
            const tuple = ecs.getEntityComponents(entity, &.{ TestingTypes.Position, TestingTypes.Collider }).?;
            try std.testing.expectEqual(TestingTypes.Position{ .x = 2, .y = 1 }, tuple[0].*);
            try std.testing.expectEqual(TestingTypes.Collider{ .x = 5, .y = 5 }, tuple[1].*);
        }
    }

    const entity = ecs.createEntity(.{ TestingTypes.Collider{ .x = 5, .y = 5 }, TestingTypes.Position{ .x = 4, .y = 4 } }, &.{TestingTypes.Tag});

    try std.testing.expect(ecs.entityHas(entity, TestingTypes.Collider));
    try std.testing.expect(ecs.entityHas(entity, TestingTypes.Tag));
}

test "Destroing an entity" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    const entity_ptr = ecs.createEntity(
        .{TestingTypes.Position{ .x = 1, .y = 1 }},
        &.{},
    );

    try std.testing.expect(ecs.entityIsValid(entity_ptr) == true);

    ecs.destroyEntity(entity_ptr);

    ecs.clearDestroyedEntitys();
    try std.testing.expect(ecs.destroyed_entitys.items.len == 0);
    try std.testing.expect(ecs.unused_entitys.items.len == 1);

    try std.testing.expect(ecs.entityIsValid(entity_ptr) == false);

    const entity_ptr2 = ecs.createEntity(
        .{TestingTypes.Position{ .x = 1, .y = 1 }},
        &.{},
    );

    try std.testing.expect(ecs.entityIsValid(entity_ptr2) == true);

    try std.testing.expect(entity_ptr.entity.value() == entity_ptr2.entity.value());
    try std.testing.expect(entity_ptr.generation.value() == entity_ptr2.generation.value() - 1);
}

test "Hashmap integrity" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    var list: std.ArrayList(EntityPointer) = .empty;
    defer list.deinit(std.testing.allocator);

    for (0..2) |_| {
        try list.append(std.testing.allocator, ecs.createEntity(
            .{ TestingTypes.Position{ .x = 6, .y = 5 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        ));
    }

    for (list.items) |entity| {
        ecs.destroyEntity(entity);
        ecs.clearDestroyedEntitys();

        for (ecs.archetypes) |archetype| {
            const entitys = archetype.row_to_entity_map.values();

            for (entitys) |capture| {
                try std.testing.expect(ecs.entityIsValid(capture));
            }
        }
    }
}

test "Deletion swap order check" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);
    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ TestingTypes.Position{ .x = 1, .y = 1 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        );
    }

    ecs.destroyEntity(.{ .entity = .make(0), .generation = .make(0) });
    ecs.clearDestroyedEntitys();

    const entities = ecs.archetypes[0].row_to_entity_map.values();

    try std.testing.expectEqual(EntityPointer{ .entity = .make(99), .generation = .make(0) }, entities[0]);
    for (entities[1..], 1..) |entity, i| {
        try std.testing.expectEqual(EntityPointer{ .entity = .make(@intCast(i)), .generation = .make(0) }, entity);
    }
}

test "Iterating over a component" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ TestingTypes.Position{ .x = 1, .y = 1 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        );
        _ = ecs.createEntity(
            .{TestingTypes.Position{ .x = 1, .y = 1 }},
            &.{},
        );
        _ = ecs.createEntity(
            .{TestingTypes.Position{ .x = 1, .y = 1 }},
            &.{TestingTypes.Tag},
        );
    }

    var iterator = ecs.getIterator(.{ .component = TestingTypes.Position }).?;

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

    var iterator2 = ecs.getIterator(.{ .component = TestingTypes.Position, .exclude = .{ .tags = &.{TestingTypes.Tag} } }).?;

    try std.testing.expect(iterator2.buffers.len == 1);
    try std.testing.expect(iterator2.buffers[0].len == 100);

    while (iterator2.next()) |position| {
        try std.testing.expect(position.x == 5);
        try std.testing.expect(position.y == 2);
    }
}

test "Checking iterator entitys" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);
    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ TestingTypes.Position{ .x = 1, .y = 1 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        );
    }

    {
        var iterator = ecs.getIterator(.{ .component = TestingTypes.Position }).?;

        var i: u32 = 0;
        while (iterator.next()) |_| : (i += 1) {
            try std.testing.expectEqual(
                EntityPointer{ .entity = @enumFromInt(i), .generation = .make(0) },
                iterator.getCurrentEntity(),
            );
        }
    }

    {
        ecs.destroyEntity(.{ .entity = .make(0), .generation = .make(0) });
        ecs.clearDestroyedEntitys();

        var iterator = ecs.getIterator(.{ .component = TestingTypes.Position }).?;

        if (iterator.next()) |_| {
            try std.testing.expectEqual(EntityPointer{ .entity = .make(99), .generation = .make(0) }, iterator.getCurrentEntity());
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "Iterating over multiple components" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    for (0..100) |_| {
        _ = ecs.createEntity(
            .{ TestingTypes.Position{ .x = 6, .y = 5 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
            &.{TestingTypes.Tag},
        );
        _ = ecs.createEntity(
            .{TestingTypes.Position{ .x = 1, .y = 1 }},
            &.{},
        );
        _ = ecs.createEntity(
            .{TestingTypes.Position{ .x = 1, .y = 1 }},
            &.{TestingTypes.Tag},
        );
    }

    var iterator = ecs.getTupleIterator(.{ .include = .{ .components = &.{ TestingTypes.Position, TestingTypes.Collider } } }).?;

    try std.testing.expect(iterator.tuple_of_buffers[0].len == 1);
    try std.testing.expect(iterator.tuple_of_buffers[0][0].len == 100);

    while (iterator.next()) |components| {
        try std.testing.expect(components[0].x == 6);
        try std.testing.expect(components[0].y == 5);
        components[0].x = 7;
        components[0].y = 7;
    }

    var iterator2 = ecs.getTupleIterator(.{ .include = .{ .components = &.{ TestingTypes.Position, TestingTypes.Collider } } }).?;

    while (iterator2.next()) |components| {
        try std.testing.expect(components[0].x == 7);
        try std.testing.expect(components[0].y == 7);
    }
}

test "Singletons" {
    var ecs: TestingTypes.EcsType = try .init(std.testing.allocator);

    defer ecs.deinit();

    const entity1 = ecs.createEntity(
        .{ TestingTypes.Position{ .x = 6, .y = 5 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
        &.{TestingTypes.Tag},
    );

    const entity2 = ecs.createEntity(
        .{TestingTypes.Position{ .x = 1, .y = 1 }},
        &.{},
    );

    const entity3 = ecs.createEntity(
        .{TestingTypes.Position{ .x = 1, .y = 1 }},
        &.{TestingTypes.Tag},
    );

    { // NOTE: Checks if entity that doesn't match singleton requirments can be assigned to the sigleton.
        const singleton = ecs.createSingleton(.{ .components = &.{TestingTypes.Position}, .tags = &.{TestingTypes.Tag} });
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

    { // NOTE: Checks updating of singletons entity.
        const singleton = ecs.createSingleton(.{ .components = &.{TestingTypes.Position} });
        try std.testing.expect(ecs.getSingletonsEntity(singleton) == null);

        ecs.setSingletonsEntity(singleton, entity1) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity1.entity);

        ecs.setSingletonsEntity(singleton, entity2) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity2.entity);

        ecs.setSingletonsEntity(singleton, entity3) catch return error.TestUnexpectedResult;
        try std.testing.expect(ecs.getSingletonsEntity(singleton).?.entity == entity3.entity);
    }
}

test "Links" {
    const EcsType = Ecs(&.{
        .{ .components = &.{TestingTypes.Collider} },
        .{ .components = &.{ TestingTypes.Position, TestingTypes.Collider }, .tags = &.{TestingTypes.Tag} },
        .{ .components = &.{TestingTypes.Position} },
        .{ .components = &.{TestingTypes.Position}, .tags = &.{TestingTypes.Tag} },
    }, &.{.{ .name = "parent", .T = TestingTypes.Position, .mode = .both, .requirments = .{ .components = &.{TestingTypes.Position} } }});

    var ecs: EcsType = try .init(std.testing.allocator);
    defer ecs.deinit();

    const entity_1 = ecs.createEntity(
        .{ TestingTypes.Position{ .x = 6, .y = 5 }, TestingTypes.Collider{ .x = 5, .y = 5 } },
        &.{TestingTypes.Tag},
    );

    const entity_2 = ecs.createEntity(
        .{TestingTypes.Position{ .x = 1, .y = 1 }},
        &.{},
    );

    const entity_3 = ecs.createEntity(
        .{TestingTypes.Collider{ .x = 1, .y = 1 }},
        &.{},
    );

    try ecs.createLink("parent", entity_1, entity_2, TestingTypes.Position{ .x = 1, .y = 1 });
    try std.testing.expectError(error.EntityNotMatchRequirments, ecs.createLink("parent", entity_1, entity_3, TestingTypes.Position{ .x = 1, .y = 1 }));

    {
        const links = ecs.getLinks("parent");

        try std.testing.expectEqualSlices(EntityPointer, &.{entity_1}, links.sources);
        try std.testing.expectEqualSlices(EntityPointer, &.{entity_2}, links.destinations);
        try std.testing.expectEqualSlices(TestingTypes.Position, &.{.{ .x = 1, .y = 1 }}, links.data);
    }
    ecs.destroyLink("parent", entity_1, entity_2) catch unreachable;
    try ecs.createLink("parent", entity_2, entity_1, TestingTypes.Position{ .x = 1, .y = 1 });

    ecs.destroyEntity(entity_2);
    ecs.clearDestroyedEntitys();

    {
        const links = ecs.getLinks("parent");

        try std.testing.expectEqualSlices(EntityPointer, &.{}, links.sources);
        try std.testing.expectEqualSlices(EntityPointer, &.{}, links.destinations);
        try std.testing.expectEqualSlices(TestingTypes.Position, &.{}, links.data);
    }
}
