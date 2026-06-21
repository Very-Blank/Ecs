const std = @import("std");
const ecs = @import("ecs.zig");
const help = @import("help.zig");

const EntityType = ecs.EntityType;
const EntityPointer = ecs.EntityPointer;
const Template = ecs.Template;
const NonExhaustiveEnum = ecs.NonExhaustiveEnum;

const TupleArrayList = @import("TupleArrayList.zig");

pub const ArchetypeType = NonExhaustiveEnum(u32, opaque {});
pub const RowType = NonExhaustiveEnum(u32, opaque {});

pub fn Archetype(comptime component_count: usize, comptime tag_count: usize) type {
    return struct {
        tuple_array_list: TupleArrayList,
        entity_to_row_map: std.AutoHashMapUnmanaged(EntityType, RowType),
        row_to_entity_map: std.array_hash_map.Auto(RowType, EntityPointer),
        component_ids: []usize,

        component_bitset: std.bit_set.StaticBitSet(component_count),
        tag_bitset: std.bit_set.StaticBitSet(tag_count),

        const Self = @This();

        pub fn init(
            comptime items: []const type,
            ids: []const usize,
            component_bitset: std.bit_set.StaticBitSet(component_count),
            tag_bitset: std.bit_set.StaticBitSet(tag_count),
            allocator: std.mem.Allocator,
        ) !Self {
            const component_ids = try allocator.alloc(usize, ids.len);
            errdefer allocator.free(component_ids);
            @memcpy(component_ids, ids);

            return .{
                .tuple_array_list = .init(items),
                .entity_to_row_map = .empty,
                .row_to_entity_map = .empty,
                .component_ids = component_ids,

                .component_bitset = component_bitset,
                .tag_bitset = tag_bitset,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.tuple_array_list.deinit(&self.tuple_array_list, allocator);

            self.entity_to_row_map.deinit(allocator);
            self.row_to_entity_map.deinit(allocator);
            allocator.free(self.component_ids);
        }

        pub fn append(self: *Self, comptime items: []const type, entity_ptr: EntityPointer, components: @Tuple(items), allocator: std.mem.Allocator) !void {
            try self.tuple_array_list.append(items, components, allocator);

            try self.entity_to_row_map.put(allocator, entity_ptr.entity, RowType.make(@intCast(self.tuple_array_list.count - 1)));
            try self.row_to_entity_map.put(allocator, RowType.make(@intCast(self.tuple_array_list.count - 1)), entity_ptr);
        }

        pub fn popRemove(self: *Self, comptime items: []const type, entity_ptr: EntityPointer, allocator: std.mem.Allocator) !@Tuple(items) {
            const row: RowType = self.entity_to_row_map.get(entity_ptr.entity) orelse unreachable;

            const old_components: @Tuple(items) = self.tuple_array_list.swapRemove(items, row.value());

            if (row.value() == self.tuple_array_list.count - 1 or self.tuple_array_list.count == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.swapRemove(row));
            } else {
                const end_row = RowType.make(@intCast(self.tuple_array_list.count));
                const row_end_entity_ptr = self.row_to_entity_map.get(end_row) orelse unreachable;

                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.swapRemove(row));

                try self.entity_to_row_map.put(allocator, row_end_entity_ptr.entity, row);
                try self.row_to_entity_map.put(allocator, row, row_end_entity_ptr);
            }

            return old_components;
        }

        pub fn remove(self: *Self, entity_ptr: EntityPointer, allocator: std.mem.Allocator) !void {
            const row: RowType = self.entity_to_row_map.get(entity_ptr.entity) orelse unreachable;

            self.tuple_array_list.remove(&self.tuple_array_list, row.value(), allocator);

            if (row.value() == self.row_to_entity_map.values().len - 1 or self.row_to_entity_map.values().len == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
                std.debug.assert(self.row_to_entity_map.swapRemove(row));

                return;
            }

            const end_row = RowType.make(@intCast(self.tuple_array_list.count));
            const row_end_entity_ptr = self.row_to_entity_map.get(end_row) orelse unreachable;

            std.debug.assert(self.entity_to_row_map.remove(entity_ptr.entity));
            std.debug.assert(self.row_to_entity_map.swapRemove(row));

            try self.entity_to_row_map.put(allocator, row_end_entity_ptr.entity, row);
            try self.row_to_entity_map.put(allocator, row, row_end_entity_ptr);
        }

        pub inline fn getEntityRowIndex(self: *Self, entity_ptr: EntityPointer) usize {
            return self.entity_to_row_map.get(entity_ptr.entity).?.value();
        }

        pub inline fn getItemArray(self: *Self, comptime component: type, component_id: usize) []component {
            for (self.component_ids, 0..) |id, i| {
                if (component_id == id) return self.tuple_array_list.getItemArray(component, i);
            }

            unreachable;
        }
    };
}
