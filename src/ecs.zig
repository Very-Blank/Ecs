const std = @import("std");
const help = @import("help.zig");

const GenericIterator = @import("iterator.zig").GenericIterator;
const GenericTupleIterator = @import("tupleIterator.zig").GenericTupleIterator;
const TupleOfBuffers = help.TupleOfBuffers;

const Template = @import("Template.zig");
const TupleFilter = @import("TupleFilter.zig");
const Filter = @import("Filter.zig");
const Registry = @import("registery.zig").Registry;

const Header = @import("header.zig").Header;
const Field = @import("header.zig").Field;

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
    switch (@typeInfo(T)) {
        .int => |info| if (info.signedness != .unsigned) {},
        else => @compileError("Unexpected type was given: " ++ @typeName(T) ++ ", expected an unsiged integer."),
    }

    if (@typeInfo(Unique) != .@"opaque")
        @compileError("Unexpected type was given: " ++ @typeName(Unique) ++ ", expected an opaque.");

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

pub const EntityID = NonExhaustiveEnum(u32, opaque {});
pub const Generation = NonExhaustiveEnum(u32, opaque {});
pub const ArchetypeID = NonExhaustiveEnum(u32, opaque {});
pub const Row = NonExhaustiveEnum(u32, opaque {});
pub const DenseIndex = NonExhaustiveEnum(u32, opaque {});

pub const EntityPointer = struct {
    entity: EntityID,
    generation: Generation,

    pub inline fn eql(self: EntityPointer, other: EntityPointer) bool {
        return self.entity == other.entity and self.generation == other.generation;
    }
};

const MainHeader = Header(&.{
    Field{ .name = "length", .type = u32 },
    Field{ .name = "entity_count", .type = u32, .default_value_ptr = &@as(u32, 0) },
    Field{ .name = "entity_capacity", .type = u32 },
}, 4);

const ArchetypeHeader = Header(&.{
    Field{ .name = "count", .type = u32, .default_value_ptr = &@as(u32, 0) },
    Field{ .name = "capacity", .type = u32 },
    Field{ .name = "component_offset", .type = u32 },
    Field{ .name = "entities_offset", .type = u32 },
    Field{ .name = "component_bitset", .type = std.bit_set.IntegerBitSet(128) },
    Field{ .name = "tag_bitset", .type = std.bit_set.IntegerBitSet(128) },
}, 0);

// FIXME: limit components to 128 and fix registery.
pub fn Ecs(
    comptime templates: []const Template,
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
        ptr: [*]align(16) u8,

        const Self = @This();

        pub const Singleton = struct { Components.Bitset, Tags.Bitset };

        pub const Components = Registry(templates, "components");

        pub const Tags = Registry(templates, "tags");

        pub const Archetypes = struct {
            pub fn getByBitset(component_bitset: Components.Bitset, tag_bitset: Tags.Bitset) !ArchetypeID {
                for (templates, 0..) |template, i| {
                    if (Components.bitset(template.components) == component_bitset and tag_bitset == Tags.bitset(template.components)) return .make(i);
                }

                return error.ArchetypeDoesNotExist;
            }

            pub fn getByTemplate(other: Template) !ArchetypeID {
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
            ) [matchingCount(include_components, include_tags, exclude_components, exclude_tags)]ArchetypeID {
                const component_bitset: Components.Bitset = Components.bitset(include_components);
                const tag_bitset: Tags.Bitset = Tags.bitset(include_tags);

                const exclude_component_bitset: Components.Bitset = Components.bitset(exclude_components);
                const exclude_tag_bitset: Tags.Bitset = Tags.bitset(exclude_tags);

                const matching_archetype_count: usize = matchingCount(include_components, include_tags, exclude_components, exclude_tags);
                if (matching_archetype_count == 0) @compileError("No matching archetypes with the supplied include and exclude.");

                var archetype_indices: [matching_archetype_count]ArchetypeID = undefined;

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

        pub fn init(capacities: [templates.len]u32, allocator: std.mem.Allocator) !Self {
            comptime if (-MainHeader.size() & (ArchetypeHeader.alignment() - 1) != 0)
                @compileError("The assumption of zero padding in between EcsHeader and ArchetypeHeaders doesn't hold.");

            comptime if (!(ArchetypeHeader.arrayable()))
                @compileError("The assumption of zero padding in between ArchetypeHeaders doesn't hold.");

            comptime if (-(MainHeader.size() + ArchetypeHeader.size() * @as(comptime_int, templates.len)) & (@alignOf(u32) - 1) != 0)
                @compileError("The assumption of zero padding after ArchetypeHeaders doesn't hold.");

            var component_counts: [Components.types.len]u32 = .{0} ** Components.types.len;
            var component_buffer_starts: [Components.types.len]u32 = .{0} ** Components.types.len;
            var start_offsets: u32 = 0;

            var entity_capacity: u32 = 0;
            inline for (templates, 0..) |template, i| {
                entity_capacity += capacities[i];
                start_offsets += template.components.len;

                inline for (template.components) |component| {
                    component_counts[comptime Components.id(component)] += capacities[i];
                }
            }

            var offset: u32 = @intCast((comptime MainHeader.size() + (ArchetypeHeader.size() * templates.len)) + start_offsets + (entity_capacity * 5));
            inline for (Components.types[0..], 0..) |component, i| {
                offset += -%offset & (@alignOf(component) - 1);
                component_buffer_starts[i] = offset;
                offset += component_counts[i];
            }

            const length = offset;

            var ecs: Self = .{ .ptr = (try allocator.alignedAlloc(u8, .@"16", length)).ptr };

            ecs.main().write(.{
                .length = length,
                .entity_capacity = entity_capacity,
            });

            inline for (templates, 0..) |template, i| {
                ecs.archetype(.make(i)).write(.{
                    .capacity = capacities[i],
                    .component_offset = 80085,
                    .entities_offset = 80085,
                    .component_bitset = comptime Components.bitset(template.components),
                    .tag_bitset = comptime Tags.bitset(template.tags),
                });
            }

            std.debug.print("{any}", .{@as([*]u32, @ptrCast(ecs.ptr))[0..20]});

            return ecs;
        }

        pub fn initFromSlice(_: []const u8, _: std.mem.Allocator) !Self {
            @compileError("TODO");
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.ptr[0..self.main().field("length").*]);
        }

        inline fn main(self: *Self) MainHeader {
            return .{ .ptr = self.ptr };
        }

        inline fn archetype(self: *Self, id: ArchetypeID) ArchetypeHeader {
            std.debug.assert(id.value() < templates.len);

            return .{ .ptr = self.ptr + (comptime MainHeader.size()) + (comptime ArchetypeHeader.size()) * id.value() };
        }

        // inline fn singleton(_: *Self, _: SingletonType) Singleton {
        //     // std.debug.assert(singleton_type.value() < self.singletons.items.len);
        //     @compileError("TODO");
        // }

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
        // pub fn createSingleton(_: *Self, comptime requirements: Template) SingletonType {
        //     const component_bitset: Components.Bitset = comptime Components.bitset(requirements.components);
        //     const tag_bitset: Tags.Bitset = comptime Tags.bitset(requirements.tags);
        //
        //     comptime check: {
        //         for (templates) |template| {
        //             const archetype_component_bitest = Components.bitset(template.components);
        //             const archetype_tags_bitest = Tags.bitset(template.tags);
        //
        //             if (archetype_component_bitest.supersetOf(component_bitset) and
        //                 archetype_tags_bitest.supersetOf(tag_bitset))
        //             {
        //                 break :check;
        //             }
        //         }
        //
        //         @compileError("No matching archetype.");
        //     }
        //
        //     @compileError("TODO");
        //
        //     // self.singletons.append(self.allocator, .{ component_bitset, tag_bitset }) catch unreachable;
        //     // return SingletonType.make(@intCast(self.singletons.items.len - 1));
        // }

        /// Sets the singleton to point to an entity if the entity matches the singletons requirments.
        /// If the entity's components or tags change and it no longer matches the singletons requirments the entity will be cleared.
        // pub fn setSingletonsEntity(_: *Self, _: SingletonType, _: EntityPointer) !void {
        //     // std.debug.assert(self.entityIsValid(entity_ptr));
        //     // std.debug.assert(singleton_type.value() < self.singletons.items.len);
        //     //
        //     // const component_bitset, const tag_bitset = self.singleton(singleton_type);
        //     //
        //     // const archetype_type: ArchetypeType = self.entity_to_archetype_map.get(entity_ptr.entity).?.archetype;
        //     //
        //     // if (self.archetype(archetype_type).component_bitset.supersetOf(component_bitset) and
        //     //     self.archetype(archetype_type).tag_bitset.supersetOf(tag_bitset))
        //     // {
        //     //     return self.singleton_to_entity_map.put(self.allocator, singleton_type, entity_ptr) catch @panic("OOM");
        //     // }
        //     //
        //     // return error.EntityNotMatchRequirments;
        //     //
        //     @compileError("TODO");
        // }

        /// Clears the set entity from the singleton.
        // pub fn clearSingletonsEntity(_: *Self, _: SingletonType) void {
        //     @compileError("TODO");
        //     // std.debug.assert(self.singleton_to_entity_map.remove(singleton_type));
        // }

        // FIXME: entity might not be in the archetype anymore!

        /// Gets the entity that is pointed by the singleton.
        // pub fn getSingletonsEntity(_: *Self, _: SingletonType) ?EntityPointer {
        //     @compileError("TODO");
        //     // std.debug.assert(singleton_type.value() < self.singletons.items.len);
        //     //
        //     // if (self.singleton_to_entity_map.get(singleton_type)) |entity| {
        //     //     if (self.entityIsValid(entity)) {
        //     //         return entity;
        //     //     }
        //     //
        //     //     std.debug.assert(self.singleton_to_entity_map.remove(singleton_type));
        //     // }
        //     //
        //     // return null;
        // }

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

        pub fn linksBySource(_: *const Self, comptime _: []const u8, _: EntityID) []const usize {
            @compileError("TODO");
            // @field(self.links, name).linksBySource(src);
        }

        pub fn linksByDestination(_: *const Self, comptime _: []const u8, _: EntityID) []const usize {
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

        // pub fn getLinks(
        //     _: *Self,
        //     comptime name: []const u8,
        // ) struct {
        //     sources: []const EntityPointer,
        //     destinations: []const EntityPointer,
        //     data: []const @FieldType(@FieldType(Self, "links"), name).InnerType,
        // } {
        //     @compileError("TODO");
        //     // return .{
        //     //     .sources = @field(self.links, name).getSources(),
        //     //     .destinations = @field(self.links, name).getDestinations(),
        //     //     .data = @field(self.links, name).getData(),
        //     // };
        // }
    };
}

test "Init" {
    const allocator = std.testing.allocator;

    const Data = struct { x: u16 };
    const EcsType = Ecs(&.{Template{ .components = &.{Data} }});

    var ecs: EcsType = try .init(.{10}, allocator);
    ecs.deinit(allocator);
}
