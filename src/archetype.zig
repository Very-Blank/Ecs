const std = @import("std");
const ct = @import("comptimeTypes.zig");

const EntityType = @import("ecs.zig").EntityType;
const EntityPointer = @import("ecs.zig").EntityPointer;
const Template = @import("ecs.zig").Template;
const Allocator = std.mem.Allocator;

const TupleArrayList = @import("tupleArrayList.zig").TupleArrayList;

pub const ArchetypeType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) ArchetypeType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": ArchetypeType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const RowType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) RowType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": RowType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub fn Archetype(
    comptime template: Template,
    comptime component_count: usize,
    comptime ComponentBitset: std.bit_set.StaticBitSet(component_count),
    comptime tag_count: usize,
    comptime TagBitset: std.bit_set.StaticBitSet(tag_count),
) type {
    return struct {
        comptime template: Template = template,

        tuple_array_list: TupleArrayList(template.components),
        entity_to_row_map: std.AutoHashMapUnmanaged(EntityType, RowType),
        row_to_entity_map: std.AutoHashMapUnmanaged(RowType, EntityPointer),
        entitys: std.ArrayList(EntityPointer),

        const Self = @This();
        pub const component_bitset: std.bit_set.StaticBitSet(component_count) = ComponentBitset;
        pub const tag_bitset: std.bit_set.StaticBitSet(tag_count) = TagBitset;

        pub const init: Self = .{
            .tuple_array_list = .empty,
            .entity_to_row_map = .empty,
            .row_to_entity_map = .empty,
            .entitys = .empty,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (template.components, 0..) |component, i| {
                const deinit_fn = init: {
                    if (!@hasDecl(component, "deinit")) continue;
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |deinit_fn| break :init deinit_fn,
                        else => continue,
                    }
                };

                if (deinit_fn.params.len > 0) {
                    const parameter1: type = deinit_fn.params[0].type orelse continue;
                    switch (@typeInfo(parameter1)) {
                        .pointer => |pointer| if (pointer.child != component) continue,
                        else => continue,
                    }

                    if (deinit_fn.params.len == 1) {
                        for (0..self.tuple_array_list.count) |j| {
                            self.tuple_array_list.tuple_of_many_ptrs[i][j].deinit();
                        }
                    } else if (deinit_fn.params.len == 2 and
                        (deinit_fn.params[1].type orelse continue) == std.mem.Allocator)
                    {
                        for (0..self.tuple_array_list.count) |j| {
                            self.tuple_array_list.tuple_of_many_ptrs[i][j].deinit(allocator);
                        }
                    } else {
                        continue;
                    }
                }
            }

            self.tuple_array_list.deinit(allocator);

            self.entity_to_row_map.deinit(allocator);
            self.row_to_entity_map.deinit(allocator);
            self.entitys.deinit(allocator);
        }

        pub fn append(self: *Self, entity_ptr: EntityPointer, components: ct.TupleOfItems(template.components), allocator: std.mem.Allocator) !void {
            try self.tuple_array_list.append(components, allocator);

            try self.entitys.append(allocator, entity_ptr);

            try self.entity_to_row_map.put(allocator, entity_ptr.entity, RowType.make(@intCast(self.entitys.items.len - 1)));
            try self.row_to_entity_map.put(allocator, RowType.make(@intCast(self.entitys.items.len - 1)), entity_ptr);
        }

        pub fn popRemove(self: *Self, entity_ptr: EntityPointer, allocator: std.mem.Allocator) !ct.TupleOfItems(template.components) {
            const row: RowType = self.entity_to_row_map.get(entity_ptr.entity) orelse unreachable;

            const old_components: ct.TupleOfItems(template.components) = init: {
                const old_components: ct.TupleOfItems(template.components) = self.tuple_array_list.swapRemove(row.value());

                break :init old_components;
            };

            if (row.value() == self.entitys.items.len - 1 or self.entitys.items.len == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.remove(row));
            } else {
                const end_row = RowType.make(@intCast(self.tuple_array_list.count));
                const row_end_entity_ptr = self.row_to_entity_map.get(end_row) orelse unreachable;

                try self.entity_to_row_map.put(allocator, row_end_entity_ptr.entity, row);
                try self.row_to_entity_map.put(allocator, row, row_end_entity_ptr);

                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.remove(end_row));
            }

            _ = self.entitys.swapRemove(row.value());

            return old_components;
        }

        pub fn remove(self: *Self, entity_ptr: EntityPointer, allocator: std.mem.Allocator) !void {
            const row: RowType = self.entity_to_row_map.get(entity_ptr.entity) orelse unreachable;

            var old_components = self.tuple_array_list.swapRemove(row.value());
            inline for (template.components, 0..) |component, i| {
                const deinit_fn = init: {
                    if (!@hasDecl(component, "deinit")) continue;
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |deinit_fn| break :init deinit_fn,
                        else => continue,
                    }
                };

                if (deinit_fn.params.len > 0) {
                    const parameter1: type = deinit_fn.params[0].type orelse continue;
                    switch (@typeInfo(parameter1)) {
                        .pointer => |pointer| if (pointer.child != component) continue,
                        else => continue,
                    }

                    if (deinit_fn.params.len == 1) {
                        old_components[i].deinit();
                    } else if (deinit_fn.params.len == 2 and
                        (deinit_fn.params[1].type orelse continue) == std.mem.Allocator)
                    {
                        old_components[i].deinit(allocator);
                    } else {
                        continue;
                    }
                }
            }

            if (row.value() == self.entitys.items.len - 1 or self.entitys.items.len == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.remove(row));
            } else {
                const end_row = RowType.make(@intCast(self.tuple_array_list.count));
                const row_end_entity = self.row_to_entity_map.get(end_row) orelse unreachable;

                try self.entity_to_row_map.put(allocator, row_end_entity.entity, row);
                try self.row_to_entity_map.put(allocator, row, row_end_entity);

                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.remove(end_row));
            }

            _ = self.entitys.swapRemove(row.value());
        }
    };
}
