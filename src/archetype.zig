const std = @import("std");
const ct = @import("comptimeTypes.zig");

const EntityType = @import("ecs.zig").EntityType;
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
        row_to_entity_map: std.AutoHashMapUnmanaged(RowType, EntityType),
        entitys: std.ArrayListUnmanaged(EntityType),

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
                if (@hasDecl(component, "deinit")) {
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |@"fn"| {
                            if (@"fn".params.len == 1) {
                                const param_type = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                switch (@typeInfo(param_type)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component) {
                                            for (0..self.tuple_array_list.count) |j| {
                                                self.tuple_array_list.tuple_of_many_ptrs[i][j].deinit();
                                            }
                                        }
                                    },
                                    else => {},
                                }
                            }

                            if (@"fn".params.len == 2) {
                                const param_type_1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                const param_type_2 = if (@"fn".params[1].type) |@"type"| @"type" else return;

                                switch (@typeInfo(param_type_1)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component and param_type_2 == std.mem.Allocator) {
                                            for (0..self.tuple_array_list.count) |j| {
                                                self.tuple_array_list.tuple_of_many_ptrs[i][j].deinit(allocator);
                                            }
                                        }
                                    },
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
            }

            self.tuple_array_list.deinit(allocator);

            self.entity_to_row_map.deinit(allocator);
            self.row_to_entity_map.deinit(allocator);
            self.entitys.deinit(allocator);
        }

        pub fn append(self: *Self, entity: EntityType, components: ct.TupleOfItems(template.components), allocator: std.mem.Allocator) !void {
            try self.tuple_array_list.append(components, allocator);

            try self.entitys.append(allocator, entity);
            try self.entity_to_row_map.put(allocator, entity, RowType.make(@intCast(self.entitys.items.len - 1)));
            try self.row_to_entity_map.put(allocator, RowType.make(@intCast(self.entitys.items.len - 1)), entity);
        }

        pub fn popRemove(self: *Self, entity: EntityType, allocator: std.mem.Allocator) !ct.TupleOfItems(template.components) {
            const row: RowType = if (self.entity_to_row_map.get(entity)) |row| row else {
                unreachable;
            };

            const old_components: ct.TupleOfItems(template.components) = init: {
                const old_components: ct.TupleOfItems(template.components) = self.tuple_array_list.swapRemove(row.value());

                break :init old_components;
            };

            if (row.value() == self.entitys.items.len - 1 or self.entitys.items.len == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity));
                std.debug.assert(self.row_to_entity_map.remove(row));
                _ = self.entitys.swapRemove(row.value());
            } else {
                const row_end_entity = if (self.row_to_entity_map.get(RowType.make(@intCast(self.entitys.items.len - 1)))) |endEntity| endEntity else {
                    unreachable;
                };

                try self.entity_to_row_map.put(allocator, row_end_entity, row);
                try self.row_to_entity_map.put(allocator, row, row_end_entity);

                _ = self.entitys.swapRemove(row.value());
                std.debug.assert(self.entity_to_row_map.remove(entity));
                std.debug.assert(self.row_to_entity_map.remove(RowType.make(@intCast(self.entitys.items.len - 1))));
            }

            return old_components;
        }

        pub fn remove(self: *Self, entity: EntityType, allocator: std.mem.Allocator) !void {
            const row: RowType = if (self.entity_to_row_map.get(entity)) |row| row else {
                unreachable;
            };

            var old_components = self.tuple_array_list.swapRemove(row.value());
            inline for (template.components, 0..) |component, i| {
                if (@hasDecl(component, "deinit")) {
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |@"fn"| {
                            if (@"fn".params.len == 1) {
                                const param_type = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                switch (@typeInfo(param_type)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component) {
                                            old_components[i].deinit();
                                        }
                                    },
                                    else => {},
                                }
                            }

                            if (@"fn".params.len == 2) {
                                const param_type_1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                const param_type_2 = if (@"fn".params[1].type) |@"type"| @"type" else return;

                                switch (@typeInfo(param_type_1)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component and param_type_2 == std.mem.Allocator) {
                                            old_components[i].deinit(allocator);
                                        }
                                    },
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
            }

            if (row.value() == self.entitys.items.len - 1 or self.entitys.items.len == 1) {
                std.debug.assert(self.entity_to_row_map.remove(entity));
                std.debug.assert(self.row_to_entity_map.remove(row));
                _ = self.entitys.swapRemove(row.value());
            } else {
                const row_end_entity = if (self.row_to_entity_map.get(RowType.make(@intCast(self.entitys.items.len - 1)))) |endEntity| endEntity else {
                    unreachable;
                };

                try self.entity_to_row_map.put(allocator, row_end_entity, row);
                try self.row_to_entity_map.put(allocator, row, row_end_entity);

                _ = self.entitys.swapRemove(row.value());
                std.debug.assert(self.entity_to_row_map.remove(entity));
                std.debug.assert(self.row_to_entity_map.remove(RowType.make(@intCast(self.entitys.items.len - 1))));
            }
        }
    };
}
