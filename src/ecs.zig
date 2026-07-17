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

const Layout = @import("layout.zig").Layout;
const Region = @import("layout.zig").Region;

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

        pub inline fn value(self: Self) T {
            return @intFromEnum(self);
        }

        pub inline fn next(self: Self) Self {
            return .make(value(self) + 1);
        }
    };
}

pub const EntityID = NonExhaustiveEnum(u32, opaque {});
pub const Generation = NonExhaustiveEnum(u32, opaque {});
pub const ArchetypeID = NonExhaustiveEnum(u32, opaque {});
pub const Row = NonExhaustiveEnum(u32, opaque {});
pub const State = enum(u32) {
    dead = 1,
    zombie = 2,
    alive = 3,
};

pub const ComponentID = NonExhaustiveEnum(u32, opaque {});
pub const TagID = NonExhaustiveEnum(u32, opaque {});

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
    Field{ .name = "dead_entity_count", .type = u32, .default_value_ptr = &@as(u32, 0) },
}, 0);

const ArchetypeHeader = Header(&.{
    Field{ .name = "count", .type = u32, .default_value_ptr = &@as(u32, 0) },
    Field{ .name = "capacity", .type = u32 },
    Field{ .name = "component_offset", .type = u32 },
    Field{ .name = "entities_offset", .type = u32 },
    // Field{ .name = "component_bitset", .type = std.bit_set.IntegerBitSet(128) },
    // Field{ .name = "tag_bitset", .type = std.bit_set.IntegerBitSet(128) },
}, 0);

const EntityHeader = Header(&.{
    Field{ .name = "archetype", .type = ArchetypeID },
    Field{ .name = "row", .type = Row },
    Field{ .name = "generation", .type = Generation },
    Field{ .name = "state", .type = State },
}, 0);

pub fn Ecs(
    comptime templates: []const Template,
) type {
    if (templates.len == 0)
        @compileError("Was called with an empty template array.");

    for (templates, 0..) |template, i| {
        for (i + 1..templates.len) |j| {
            if (template.eql(templates[j])) @compileError(
                std.fmt.comptimePrint(
                    "Two templates where the same which is not allowed. Template one index: {d}, template two index: {d}",
                    .{ i, j },
                ),
            );
        }
    }

    for (templates, 0..) |template, i| {
        if (template.components.len == 0) @compileError(
            std.fmt.comptimePrint(
                "Template components array was empty, which is not allowed. Template index: {d}.",
                .{i},
            ),
        );

        for (0..template.components.len) |cur_component_index| {
            if (@sizeOf(template.components[cur_component_index]) == 0)
                @compileError(std.fmt.comptimePrint(
                    "Templates component was a ZST, which is not allowed. Template index: {d}, component: {s}",
                    .{ cur_component_index, @typeName(template.components[cur_component_index]) },
                ));

            for (cur_component_index + 1..template.components.len) |nex_component_index| {
                if (template.components[cur_component_index] == template.components[nex_component_index])
                    @compileError(std.fmt.comptimePrint(
                        "Template had two of the same component. Template index: {d}, component: {s}",
                        .{ i, @typeName(template.components[cur_component_index]) },
                    ));
            }
        }

        for (0..template.tags.len) |cur_tag_index| {
            if (@sizeOf(template.tags[cur_tag_index]) != 0)
                @compileError(std.fmt.comptimePrint(
                    "Templates tag wasn't a ZST, which is not allowed. Template index: {d}, tag: {s}",
                    .{ cur_tag_index, @typeName(template.tags[cur_tag_index]) },
                ));

            for (cur_tag_index + 1..template.tags.len) |nex_tag_index| {
                if (template.tags[cur_tag_index] == template.tags[nex_tag_index])
                    @compileError(std.fmt.comptimePrint(
                        "Template had two of the same tag. Template index: {d}, tag: {s}",
                        .{ i, @typeName(template.tags[cur_tag_index]) },
                    ));
            }
        }
    }

    return struct {
        ptr: [*]align(4) u8,

        const Self = @This();

        pub const Singleton = struct { component_registery.Bitset, tag_registery.Bitset };

        pub const layout = Layout(&.{
            Region{
                .name = "main",
                .type_size = MainHeader.size(),
                .aligment = MainHeader.alignment(),
            },
            Region{
                .name = "archetypes",
                .type_size = ArchetypeHeader.size(),
                .aligment = ArchetypeHeader.alignment(),
                .count = templates.len,
            },
            Region{ .name = "offsets", .type_size = @sizeOf(u32), .aligment = @alignOf(u32), .count = init: {
                var sum = 0;
                for (templates) |template|
                    sum += template.components.len;

                break :init sum;
            } },
        });

        const component_registery = Registry(ComponentID, .component, templates);
        const tag_registery = Registry(TagID, .tag, templates);

        pub const Archetypes = struct {
            pub fn getByTemplate(template: Template) !ArchetypeID {
                if (!@inComptime()) @compileError("Must be called in comptime.");

                const component_bitset: component_registery.Bitset = component_registery.bitset(template.components);
                const tag_bitset: tag_registery.Bitset = tag_registery.bitset(template.tags);

                for (0..templates.len) |i| {
                    if (component_registery.bitsets[i].eql(component_bitset) and
                        tag_registery.bitsets[i].eql(tag_bitset))
                    {
                        return .make(i);
                    }
                }

                return error.ArchetypeDoesNotExist;
            }

            pub fn matchingCount(
                include_components: []const type,
                include_tags: []const type,
                exclude_components: []const type,
                exclude_tags: []const type,
            ) usize {
                if (!@inComptime()) @compileError("Must be called in comptime.");

                const component_bitset: component_registery.Bitset = component_registery.bitset(include_components);
                const tag_bitset: tag_registery.Bitset = tag_registery.bitset(include_tags);

                const exclude_component_bitset: component_registery.Bitset = component_registery.bitset(exclude_components);
                const exclude_tag_bitset: tag_registery.Bitset = tag_registery.bitset(exclude_tags);

                var matching_archetype_count: usize = 0;

                for (0..templates.len) |i| {
                    if (component_registery.bitsets[i].supersetOf(component_bitset) and
                        tag_registery.bitsets[i].supersetOf(tag_bitset) and
                        component_registery.bitsets[i].intersectWith(exclude_component_bitset).eql(.empty) and
                        tag_registery.bitsets[i].intersectWith(exclude_tag_bitset).eql(.empty))
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
                if (!@inComptime()) @compileError("Must be called in comptime.");

                const component_bitset: component_registery.Bitset = component_registery.bitset(include_components);
                const tag_bitset: tag_registery.Bitset = tag_registery.bitset(include_tags);

                const exclude_component_bitset: component_registery.Bitset = component_registery.bitset(exclude_components);
                const exclude_tag_bitset: tag_registery.Bitset = tag_registery.bitset(exclude_tags);

                const matching_archetype_count: usize = matchingCount(include_components, include_tags, exclude_components, exclude_tags);
                if (matching_archetype_count == 0) @compileError("No matching archetypes with the supplied include and exclude.");

                var archetype_indices: [matching_archetype_count]ArchetypeID = undefined;

                var current_index = 0;
                for (0..templates.len) |i| {
                    if (component_registery.bitsets[i].supersetOf(component_bitset) and
                        tag_registery.bitsets[i].supersetOf(tag_bitset) and
                        component_registery.bitsets[i].intersectWith(exclude_component_bitset).eql(.empty) and
                        tag_registery.bitsets[i].intersectWith(exclude_tag_bitset).eql(.empty))
                    {
                        archetype_indices[current_index] = .make(i);
                        current_index += 1;
                    }
                }

                return archetype_indices;
            }
        };

        pub fn init(capacities: [templates.len]u32, allocator: std.mem.Allocator) !Self {
            comptime if (!(ArchetypeHeader.arrayable()))
                @compileError("The assumption of zero padding in between ArchetypeHeaders doesn't hold.");

            comptime if (!(EntityHeader.arrayable()))
                @compileError("The assumption of zero padding in between EntityHeaders doesn't hold.");

            var component_counts: [component_registery.types.len]u32 = .{0} ** component_registery.types.len;
            var component_buffer_starts: [component_registery.types.len]u32 = .{0} ** component_registery.types.len;

            var entity_capacity: u32 = 0;
            inline for (templates, 0..) |template, i| {
                entity_capacity += capacities[i];
                inline for (template.components) |Component| {
                    component_counts[comptime component_registery.id(Component).value()] += capacities[i];
                }
            }

            var end: u32 = @intCast(layout.size() + ((EntityHeader.size() + @sizeOf(EntityID)) * entity_capacity));

            inline for (component_registery.types[0..], 0..) |Component, i| {
                end += -%end & (@alignOf(Component) - 1);
                component_buffer_starts[i] = end;
                end += component_counts[i];
            }

            const length = end;

            var ecs: Self = .{ .ptr = (try allocator.alignedAlloc(u8, .@"4", length)).ptr };

            ecs.main().write(.{
                .length = length,
                .entity_capacity = entity_capacity,
            });

            var current_component_offset: u32 = 0;
            var current_entity_offset: u32 = 0;

            inline for (templates, 0..) |template, i| {
                const capacity = capacities[i];

                const ids: [template.components.len]ComponentID = comptime init: {
                    var ids: [template.components.len]ComponentID = undefined;

                    for (template.components, 0..) |Component, j| {
                        ids[j] = component_registery.id(Component);
                    }

                    std.mem.sort(ComponentID, &ids, {}, struct {
                        fn lessThan(_: void, a: ComponentID, b: ComponentID) bool {
                            return a.value() < b.value();
                        }
                    }.lessThan);

                    break :init ids;
                };

                const buffer_offsets: [template.components.len]u32 = init: {
                    var buffer_offsets: [template.components.len]u32 = undefined;
                    for (ids, 0..) |id, j| {
                        buffer_offsets[j] = component_buffer_starts[id.value()];
                        component_buffer_starts[id.value()] += capacity;
                    }

                    break :init buffer_offsets;
                };

                @memcpy(
                    (@as([*]u32, @ptrCast(@alignCast(ecs.ptr + layout.regionStart("offsets")))) + current_component_offset)[0..buffer_offsets.len],
                    &buffer_offsets,
                );

                ecs.archetype(.make(i)).write(.{
                    .capacity = capacities[i],
                    .component_offset = current_component_offset,
                    .entities_offset = current_entity_offset,
                });

                current_component_offset += template.components.len;
                current_entity_offset += capacity;
            }

            return ecs;
        }

        pub fn initFromSlice(_: []const u8, _: std.mem.Allocator) !Self {
            @compileError("TODO");
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.ptr[0..self.main().field("length").*]);
        }

        inline fn main(self: Self) MainHeader {
            return .{ .ptr = self.ptr + layout.regionStart("main") };
        }

        inline fn archetype(self: Self, id: ArchetypeID) ArchetypeHeader {
            std.debug.assert(id.value() < templates.len);

            return .{ .ptr = self.ptr + layout.regionStart("archetypes") + ArchetypeHeader.size() * id.value() };
        }

        inline fn offset(self: Self, archetype_header: ArchetypeHeader, index: u32) u32 {
            return @as([*]u32, @ptrCast(@alignCast(self.ptr + layout.regionStart("offsets"))))[archetype_header.field("component_offset").* + index];
        }

        inline fn entity(self: Self, id: EntityID) EntityHeader {
            std.debug.assert(id.value() < self.main().field("entity_capacity").*);

            return .{ .ptr = self.ptr + layout.size() + (EntityHeader.size() * id.value()) };
        }

        inline fn rowsEntityID(self: Self, archetype_header: ArchetypeHeader, row: Row) *EntityID {
            return &(@as(
                [*]EntityID,
                @ptrCast(
                    @alignCast(
                        self.ptr + layout.size() + (self.main().field("entity_capacity").* * EntityHeader.size()),
                    ),
                ),
            ) + archetype_header.field("entities_offset").*)[row.value()];
        }

        inline fn component(
            self: Self,
            ptr_offset: u32,
            row: Row,
            Component: type,
        ) *Component {
            return &@as([*]Component, @ptrCast(@alignCast(self.ptr
                //
            + layout.size()
                //
            + (self.main().field("entity_capacity").* * (EntityHeader.size() + @sizeOf(EntityID)))
                //
            + ptr_offset
                //
            )))[row.value()];
        }

        inline fn componentSlice(
            self: Self,
            ptr_offset: u32,
            row: Row,
            id: ComponentID,
        ) []u8 {
            const component_size = component_registery.sizes[id.value()];

            return (self.ptr
                //
            + layout.size()
                //
            + (self.main().field("entity_capacity").* * (EntityHeader.size() + @sizeOf(EntityID)))
                //
            + ptr_offset
                //
            + row.value() * component_size
                //
            )[0..component_size];
        }

        // inline fn singleton(_: *Self, _: SingletonType) Singleton {
        //     // std.debug.assert(singleton_type.value() < self.singletons.items.len);
        //     @compileError("TODO");
        // }

        pub inline fn entityIsValid(self: Self, entity_pointer: EntityPointer) bool {
            const entity_header = self.entity(entity_pointer.entity);

            return entity_header.field("state").* != .dead and
                entity_header.field("generation").* == entity_pointer.generation and
                entity_pointer.entity.value() < self.main().field("entity_count").*;
        }

        /// Creates an entity with the spesified components and tags, adding the components to the correct archetype.
        /// Iterators will not see the new entity.
        pub fn createEntity(self: Self, components: anytype, comptime tags: []const type) EntityPointer {
            const template: Template = .{ .components = &comptime help.typesFromTuple(@TypeOf(components)), .tags = tags };
            const entity_archetype: ArchetypeID = comptime Archetypes.getByTemplate(template) catch @compileError("Archetype matching required components and tags didn't exist.");

            const new_entity_ptr: EntityPointer = init: {
                if (self.main().field("dead_entity_count").* == 0) {
                    if (self.main().field("entity_count").* == self.main().field("entity_capacity").*)
                        @panic("ECS ran out of capacity.");

                    const entity_id: EntityID = .make(self.main().field("entity_count").*);
                    self.main().field("entity_count").* += 1;

                    self.entity(entity_id).field("generation").* = Generation.make(0);

                    break :init .{
                        .entity = entity_id,
                        .generation = .make(0),
                    };
                }

                defer self.main().field("dead_entity_count").* -= 1;

                // FIXME: Very bad access pattern.
                var id: EntityID = .make(0);
                while (id.value() < self.main().field("entity_count").* and self.entity(id).field("state").* != .dead) {
                    id = id.next();
                }

                // NOTE: Would mean that we didn't find any dead entity like dead_entity_count claimed there would be.
                std.debug.assert(id.value() < self.main().field("entity_count").*);

                self.entity(id).field("generation").* = self.entity(id).field("generation").next();

                break :init .{
                    .entity = id,
                    .generation = self.entity(id).field("generation").*,
                };
            };

            const entity_header: EntityHeader = self.entity(new_entity_ptr.entity);
            const entity_archetype_header: ArchetypeHeader = self.archetype(entity_archetype);

            if (entity_archetype_header.field("count").* == entity_archetype_header.field("capacity").*)
                @panic("Archetype ran out of capacity");

            const row: Row = .make(entity_archetype_header.field("count").*);

            entity_header.field("state").* = .alive;
            entity_header.field("archetype").* = entity_archetype;
            entity_header.field("row").* = row;

            const bitset: component_registery.Bitset = component_registery.bitsets[entity_archetype.value()];

            inline for (template.components, 0..) |Component, i| {
                const index: u32 = comptime init: {
                    const id: ComponentID = component_registery.id(Component);

                    var iterator: component_registery.Iterator = .init(bitset);

                    while (iterator.next()) |capture| {
                        if (capture.id == id) break :init capture.index;
                    }

                    @compileError("OH FUCK.");
                };

                self.component(self.offset(entity_archetype_header, index), row, Component).* = components[i];
            }

            self.rowsEntityID(entity_archetype_header, row).* = new_entity_ptr.entity;

            entity_archetype_header.field("count").* += 1;

            return new_entity_ptr;
        }

        /// Marks the entity to be removed in the next clearDestroyedEntitys call.
        pub fn destroyEntity(self: Self, entity_pointer: EntityPointer) void {
            std.debug.assert(self.entityIsValid(entity_pointer));

            const entity_header: EntityHeader = self.entity(entity_pointer.entity);
            entity_header.field("state").* = .zombie;
        }

        /// Destroyes all entitys that where marked by destroyEntity.
        /// If any iterators include any of the destroyed entitys, using those iterators is undefiend behaviour.
        pub fn clearDestroyedEntitys(self: Self) void {
            if (self.main().field("dead_entity_count").* == 0) return;

            const entity_count = self.main().field("entity_count").*;

            for (0..entity_count) |i| {
                const entity_header = self.entity(.make(@intCast(i)));

                if (entity_header.field("state").* == .zombie) {
                    const entity_archetype_header: ArchetypeHeader = self.archetype(entity_header.field("archetype").*);

                    const target_row: Row = entity_header.field("row").*;
                    const end_row: Row = .make(entity_archetype_header.field("count").* - 1);

                    std.debug.assert(target_row.value() <= end_row.value());

                    if (target_row != end_row) {
                        const bitset: component_registery.Bitset = component_registery.bitsets[entity_header.field("archetype").value()];

                        const end_entity: EntityID = self.rowsEntityID(entity_archetype_header, end_row).*;

                        self.entity(end_entity).field("row").* = target_row;
                        self.rowsEntityID(entity_archetype_header, target_row).* = end_entity;

                        var iterator: component_registery.Iterator = .init(bitset);
                        while (iterator.next()) |capture| {
                            const ptr_offset: u32 = self.offset(entity_archetype_header, capture.index);

                            @memcpy(
                                self.componentSlice(ptr_offset, target_row, capture.id),
                                self.componentSlice(ptr_offset, end_row, capture.id),
                            );
                        }
                    }

                    self.main().field("dead_entity_count").* -= 1;
                    entity_archetype_header.field("count").* -= 1;

                    entity_header.field("state").* = .dead;
                }
            }
        }

        /// Takes in a tag or a component and checks if the entity has it.
        pub inline fn entityHas(
            self: Self,
            entity_pointer: EntityPointer,
            comptime T: type,
        ) bool {
            std.debug.assert(self.entityIsValid(entity_pointer));

            const entity_header = self.entity(entity_pointer.entity);

            if (comptime @sizeOf(T) != 0) {
                return tag_registery.bitsets[entity_header.field("archetype").*].isSet(comptime tag_registery.id(T));
            }

            return component_registery.bitsets[entity_header.field("archetype").*].isSet(comptime component_registery.id(T));
        }

        pub fn getEntityComponent(
            self: *Self,
            entity_pointer: EntityPointer,
            comptime Component: type,
        ) ?*Component {
            const entity_header = self.entity(entity_pointer.entity);

            if (component_registery.bitsets[entity_header.field("archetype").*].isSet(comptime component_registery.id(Component)))
                return null;

            // @compileError("TODO");
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

    const DataX = struct { x: u32 };
    const DataY = struct { y: u32 };
    const EcsType = Ecs(&.{ Template{ .components = &.{ DataX, DataY } }, Template{ .components = &.{DataX} } });

    var ecs: EcsType = try .init(.{ 10, 10 }, allocator);
    defer ecs.deinit(allocator);
    const first = ecs.createEntity(.{ DataX{ .x = 1000010000 }, DataY{ .y = 1000010000 } }, &.{});
    _ = ecs.createEntity(.{ DataX{ .x = 2000020000 }, DataY{ .y = 2000020000 } }, &.{});
    ecs.destroyEntity(first);
    std.debug.print("{any}\n", .{@as([*]u32, @ptrCast(ecs.ptr))[0..400]});
    ecs.clearDestroyedEntitys();

    std.debug.print("{any}\n", .{@as([*]u32, @ptrCast(ecs.ptr))[0..400]});
}
