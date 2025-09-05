const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;
const EntityType = @import("ecs.zig").EntityType;
const Template = @import("ecs.zig").Template;
const Allocator = std.mem.Allocator;

const compStruct = @import("comptimeStruct.zig");
const TupleOfArrayLists = @import("comptimeStruct.zig").TupleOfArrayLists;

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

        container: TupleOfArrayLists(template.components),
        entityToRowMap: std.AutoHashMapUnmanaged(EntityType, RowType),
        rowToEntityMap: std.AutoHashMapUnmanaged(RowType, EntityType),
        entitys: u32,

        const Self = @This();
        pub const componentBitset: std.bit_set.StaticBitSet(componentCount) = ComponentBitset;
        pub const tagBitset: std.bit_set.StaticBitSet(tagCount) = TagBitset;

        pub const init: Self = .{
            .container = init: {
                var container: TupleOfArrayLists(template.components) = undefined;
                for (0..template.components.len) |i| {
                    container[i] = .empty;
                }

                break :init container;
            },
            .entityToRowMap = .empty,
            .rowToEntityMap = .empty,
            .entitys = 0,
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
                                            for (self.container[i].items) |value| {
                                                value.deinit();
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
                                            for (self.container[i].items) |value| {
                                                value.deinit(allocator);
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

                self.container[i].deinit(allocator);
                self.container[i] = .empty;
            }

            self.entityToRowMap.deinit(allocator);
            self.rowToEntityMap.deinit(allocator);
        }

        pub fn append(self: *Self, entity: EntityType, components: compStruct.TupleOfComponents(template.components), allocator: std.mem.Allocator) !void {
            inline for (0..template.components.len) |i| {
                try self.container[i].append(allocator, components[i]);
            }

            try self.entityToRowMap.put(allocator, entity, RowType.make(self.entitys));
            try self.rowToEntityMap.put(allocator, RowType.make(self.entitys), entity);

            self.entitys += 1;
        }

        pub fn remove(self: *Self, entity: EntityType, allocator: std.mem.Allocator) !void {
            const row: RowType = if (self.entityToRowMap.get(entity)) |row| row else {
                unreachable;
            };

            inline for (0..template.components.len) |i| {
                _ = self.container[i].swapRemove(row.value());
            }

            if (row.value() == self.entitys - 1 or self.entitys == 1) {
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(row));
            } else {
                const rowEndEntity = if (self.rowToEntityMap.get(RowType.make(self.entitys - 1))) |endEntity| endEntity else {
                    unreachable;
                };

                try self.entityToRowMap.put(allocator, rowEndEntity, row);
                try self.rowToEntityMap.put(allocator, row, rowEndEntity);

                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(RowType.make(self.entitys - 1)));
            }

            self.entitys -= 1;
        }

        pub fn getEntitys(self: *Self) []EntityType {
            const Header = struct {
                values: [*]RowType,
                keys: [*]EntityType,
                capacity: @TypeOf(self.entityToRowMap).Size,
            };

            return @as(*Header, @ptrCast(@as([*]Header, @ptrCast(@alignCast(self.entityToRowMap.metadata.?))) - 1)).keys[0..self.entitys];
        }

        pub fn getComponentArray(self: *Self, comptime component: type) []component {
            inline for (template.components, 0..) |comp, i| {
                if (component == comp) {
                    return self.container[i].items;
                }
            }

            @compileError("Component didn't exist in the archetype. Was given " ++ @typeName(component) ++ ".");
        }
    };
}
