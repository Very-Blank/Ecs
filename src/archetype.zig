const std = @import("std");

const EntityType = @import("ecs.zig").EntityType;
const Template = @import("ecs.zig").Template;
const Allocator = std.mem.Allocator;

const compTypes = @import("comptimeTypes.zig");
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
    comptime componentCount: usize,
    comptime ComponentBitset: std.bit_set.StaticBitSet(componentCount),
    comptime tagCount: usize,
    comptime TagBitset: std.bit_set.StaticBitSet(tagCount),
) type {
    return struct {
        comptime template: Template = template,

        tupleArrayList: TupleArrayList(template.components),
        entityToRowMap: std.AutoHashMapUnmanaged(EntityType, RowType),
        rowToEntityMap: std.AutoHashMapUnmanaged(RowType, EntityType),
        entitys: std.ArrayListUnmanaged(EntityType),

        const Self = @This();
        pub const componentBitset: std.bit_set.StaticBitSet(componentCount) = ComponentBitset;
        pub const tagBitset: std.bit_set.StaticBitSet(tagCount) = TagBitset;

        pub const init: Self = .{
            .tupleArrayList = .empty,
            .entityToRowMap = .empty,
            .rowToEntityMap = .empty,
            .entitys = .empty,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (template.components, 0..) |component, i| {
                if (@hasDecl(component, "deinit")) {
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |@"fn"| {
                            if (@"fn".params.len == 1) {
                                const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                switch (@typeInfo(paramType)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component) {
                                            for (0..self.tupleArrayList.count) |j| {
                                                self.tupleArrayList.tupleOfManyPointers[i][j].deinit();
                                            }
                                        }
                                    },
                                    else => {},
                                }
                            }

                            if (@"fn".params.len == 2) {
                                const paramType1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                const paramType2 = if (@"fn".params[1].type) |@"type"| @"type" else return;

                                switch (@typeInfo(paramType1)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component and paramType2 == std.mem.Allocator) {
                                            for (0..self.tupleArrayList.count) |j| {
                                                self.tupleArrayList.tupleOfManyPointers[i][j].deinit(allocator);
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

            self.tupleArrayList.deinit(allocator);

            self.entityToRowMap.deinit(allocator);
            self.rowToEntityMap.deinit(allocator);
            self.entitys.deinit(allocator);
        }

        pub fn append(self: *Self, entity: EntityType, components: compTypes.TupleOfItems(template.components), allocator: std.mem.Allocator) !void {
            try self.tupleArrayList.append(components, allocator);

            try self.entitys.append(allocator, entity);
            try self.entityToRowMap.put(allocator, entity, RowType.make(@intCast(self.entitys.items.len - 1)));
            try self.rowToEntityMap.put(allocator, RowType.make(@intCast(self.entitys.items.len - 1)), entity);
        }

        pub fn popRemove(self: *Self, entity: EntityType, allocator: std.mem.Allocator) !compTypes.TupleOfItems(template.components) {
            const row: RowType = if (self.entityToRowMap.get(entity)) |row| row else {
                unreachable;
            };

            const oldComponents: compTypes.TupleOfItems(template.components) = init: {
                const oldComponents: compTypes.TupleOfItems(template.components) = self.tupleArrayList.swapRemove(row.value());

                break :init oldComponents;
            };

            if (row.value() == self.entitys.items.len - 1 or self.entitys.items.len == 1) {
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(row));
                _ = self.entitys.swapRemove(row.value());
            } else {
                const rowEndEntity = if (self.rowToEntityMap.get(RowType.make(@intCast(self.entitys.items.len - 1)))) |endEntity| endEntity else {
                    unreachable;
                };

                try self.entityToRowMap.put(allocator, rowEndEntity, row);
                try self.rowToEntityMap.put(allocator, row, rowEndEntity);

                _ = self.entitys.swapRemove(row.value());
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(RowType.make(@intCast(self.entitys.items.len - 1))));
            }

            return oldComponents;
        }

        pub fn remove(self: *Self, entity: EntityType, allocator: std.mem.Allocator) !void {
            const row: RowType = if (self.entityToRowMap.get(entity)) |row| row else {
                unreachable;
            };

            var oldComponents = self.tupleArrayList.swapRemove(row.value());
            inline for (template.components, 0..) |component, i| {
                if (@hasDecl(component, "deinit")) {
                    switch (@typeInfo(@TypeOf(component.deinit))) {
                        .@"fn" => |@"fn"| {
                            if (@"fn".params.len == 1) {
                                const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                switch (@typeInfo(paramType)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component) {
                                            oldComponents[i].deinit();
                                        }
                                    },
                                    else => {},
                                }
                            }

                            if (@"fn".params.len == 2) {
                                const paramType1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                const paramType2 = if (@"fn".params[1].type) |@"type"| @"type" else return;

                                switch (@typeInfo(paramType1)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == component and paramType2 == std.mem.Allocator) {
                                            oldComponents[i].deinit(allocator);
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
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(row));
                _ = self.entitys.swapRemove(row.value());
            } else {
                const rowEndEntity = if (self.rowToEntityMap.get(RowType.make(@intCast(self.entitys.items.len - 1)))) |endEntity| endEntity else {
                    unreachable;
                };

                try self.entityToRowMap.put(allocator, rowEndEntity, row);
                try self.rowToEntityMap.put(allocator, row, rowEndEntity);

                _ = self.entitys.swapRemove(row.value());
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(RowType.make(@intCast(self.entitys.items.len - 1))));
            }
        }
    };
}
