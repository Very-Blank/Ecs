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

pub fn Archetype(comptime template: Template) type {
    const componentsInfo = info: {
        const componentsInfo = compStruct.getTuple(template.components);

        inline for (componentsInfo.fields) |field| {
            if (@sizeOf(field.type) == 0) {
                @compileError("Component was a ZST, was given component " ++ @typeName(field.type) ++ ".");
            }
        }

        break :info componentsInfo;
    };

    inline for (compStruct.getTupleAllowEmpty(template.tags).fields) |field| {
        if (@sizeOf(field.type) != 0) {
            @compileError("Tags wasn't a ZST, was given tag " ++ @typeName(field.type) ++ ".");
        }
    }

    return struct {
        comptime template: Template = template,
        container: TupleOfArrayLists(template.components),
        entityToRowMap: std.AutoArrayHashMapUnmanaged(EntityType, RowType),
        rowToEntityMap: std.AutoArrayHashMapUnmanaged(RowType, EntityType),
        entitys: u32,

        const Self = @This();

        pub const init: Self = .{
            .container = init: {
                var container: TupleOfArrayLists(template.components) = undefined;
                for (0..componentsInfo.fields.len) |i| {
                    container[i] = .empty;
                }

                break :init container;
            },
            .entityToRowMap = .empty,
            .rowToEntityMap = .empty,
            .entitys = 0,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (componentsInfo.fields, 0..) |field, i| {
                if (@hasDecl(field.type, "deinit")) {
                    switch (@typeInfo(@TypeOf(field.type.deinit))) {
                        .@"fn" => |@"fn"| {
                            if (@"fn".params.len == 1) {
                                const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                switch (@typeInfo(paramType)) {
                                    .pointer => |pointer| {
                                        if (pointer.child == field.type) {
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
                                        if (pointer.child == field.type and paramType2 == std.mem.Allocator) {
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

        pub fn append(self: *Self, entity: EntityType, components: template.components, allocator: std.mem.Allocator) !void {
            inline for (0..componentsInfo.fields.len) |i| {
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

            inline for (0..componentsInfo.fields.len) |i| {
                self.container[i].swapRemove(allocator, row.value());
            }

            if (row.value() == self.entitys - 1 or self.entitys == 1) {
                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(row));
            } else {
                const rowEndEntity = if (self.rowToEntityMap.get(RowType.make(self.entitys - 1))) |endEntity| endEntity else {
                    unreachable;
                };

                self.entityToRowMap.put(allocator, rowEndEntity, row);
                self.rowToEntityMap.put(allocator, row, rowEndEntity);

                std.debug.assert(self.entityToRowMap.remove(entity));
                std.debug.assert(self.rowToEntityMap.remove(RowType.make(self.entitys - 1)));
            }

            self.entitys -= 1;
        }

        pub fn getEntitys(self: *Self) []EntityType {
            return self.entityToRowMap.keys();
        }

        pub fn getComponentArray(self: *Self, comptime component: type) []component {
            inline for (componentsInfo.fields, 0..) |field, i| {
                if (component == field.type) {
                    return self.container[i].items;
                }
            }

            @compileError("Component didn't exist in the archetype. Was given " ++ @typeName(component) ++ ".");
        }
    };
}
