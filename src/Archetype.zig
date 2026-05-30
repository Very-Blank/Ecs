const std = @import("std");
const help = @import("help.zig");

const EntityType = @import("ecs.zig").EntityType;
const EntityPointer = @import("ecs.zig").EntityPointer;
const Template = @import("ecs.zig").Template;
const NonExhaustiveEnum = @import("ecs.zig").NonExhaustiveEnum;

const TupleArrayList = @import("TupleArrayList.zig");

pub const ArchetypeType = NonExhaustiveEnum(u32, opaque {});
pub const RowType = NonExhaustiveEnum(u32, opaque {});

tuple_array_list: TupleArrayList,
entity_to_row_map: std.AutoHashMapUnmanaged(EntityType, RowType),
row_to_entity_map: std.AutoHashMapUnmanaged(RowType, EntityPointer),
entitys: std.ArrayList(EntityPointer),
component_ids: []usize,

const Self = @This();

pub fn init(comptime items: []const type, ids: []const usize, allocator: std.mem.Allocator) !Self {
    const component_ids = try allocator.alloc(usize, ids.len);
    errdefer allocator.free(component_ids);
    @memcpy(component_ids, ids);

    return .{
        .tuple_array_list = try .init(items, allocator),
        .entity_to_row_map = .empty,
        .row_to_entity_map = .empty,
        .entitys = .empty,
        .component_ids = component_ids,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.tuple_array_list.deinit(&self.tuple_array_list, allocator);

    self.entity_to_row_map.deinit(allocator);
    self.row_to_entity_map.deinit(allocator);
    self.entitys.deinit(allocator);
    allocator.free(self.component_ids);
}

pub fn append(self: *Self, comptime items: []const type, entity_ptr: EntityPointer, components: @Tuple(items), allocator: std.mem.Allocator) !void {
    try self.tuple_array_list.append(items, components, allocator);

    try self.entitys.append(allocator, entity_ptr);

    try self.entity_to_row_map.put(allocator, entity_ptr.entity, RowType.make(@intCast(self.entitys.items.len - 1)));
    try self.row_to_entity_map.put(allocator, RowType.make(@intCast(self.entitys.items.len - 1)), entity_ptr);
}

pub fn popRemove(self: *Self, comptime items: []const type, entity_ptr: EntityPointer, allocator: std.mem.Allocator) !@Tuple(items) {
    const row: RowType = self.entity_to_row_map.get(entity_ptr.entity) orelse unreachable;

    const old_components: @Tuple(items) = self.tuple_array_list.swapRemove(items, row.value());

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

    self.tuple_array_list.remove(&self.tuple_array_list, row.value(), allocator);

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

pub inline fn getEntityRowIndex(self: *Self, entity_ptr: EntityPointer) usize {
    return self.entity_to_row_map.get(entity_ptr.entity).?.value();
}

pub inline fn getItemArray(self: *Self, id: usize, comptime component: type) []component {
    for (self.component_ids, 0..) |component_id, i| {
        if (id == component_id) return self.tuple_array_list.getItemArray(i, component);
    }

    unreachable;
}
