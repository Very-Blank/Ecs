const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;
const ComponentType = @import("componentManager.zig").ComponentType;

const EntityType = @import("entity.zig").EntityType;
const ErasedArray = @import("erasedArray.zig").ErasedArray;

const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;

const Allocator = std.mem.Allocator;

const Helper = @import("helper.zig");

pub const ArchetypeType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) ArchetypeType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": ArchetypeType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const Row = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) Row {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": Row) u32 {
        return @intFromEnum(@"enum");
    }
};

pub fn Container(comptime T: type) type {
    const @"struct": std.builtin.Type.Struct = Helper.getTuple(T);
    var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;

    for (@"struct".fields, 0..) |field, i| {
        new_fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = std.ArrayListUnmanaged(field.type),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(std.ArrayListUnmanaged(field.type)),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn Archetype(comptime T: type) type {
    const @"struct": std.builtin.Type.Struct = Helper.getStruct(T);

    return struct {
        tags: [][]const u8,
        bitset: Bitset,
        container: Container(T),
        entityToRowMap: std.AutoArrayHashMapUnmanaged(EntityType, Row),
        rowToEntityMap: std.AutoArrayHashMapUnmanaged(Row, EntityType),

        const Self = @This();

        pub fn init(tags: [][]const u8, bitset: Bitset) Self {
            var result: Self = .{
                .tags = tags,
                .bitset = bitset,
                .container = undefined,
                .entityToRowMap = .empty,
                .rowToEntityMap = .empty,
            };

            inline for (0..@"struct".fields.len) |i| {
                result.container[i] = .empty;
            }

            return result;
        }

        pub fn append(components: T, allocator: std.mem.Allocator) !void {
            inline for (0..@"struct".fields.len) |i| {
                try result.container[i].append(allocator, components[i]);
            }
        }

        pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
            inline for (@"struct".fields, 0..) |field, i| {
                switch (Helper.DeinitType.new(field.type)) {
                    .nonAllocator => for (self.container[i].items) |value| {
                        value.deinit();
                    },
                    .allocator => for (self.container[i].items) |value| {
                        value.deinit(allocator);
                    },
                    else => {},
                }

                self.container[i].deinit();
            }
        }
    };
}

pub const Archetype = struct {
    bitset: Bitset,
    componentArrays: std.ArrayListUnmanaged(ErasedArray),
    components: u32,

    entityToRowMap: std.AutoArrayHashMapUnmanaged(EntityType, Row),
    rowToEntityMap: std.AutoArrayHashMapUnmanaged(Row, EntityType),
    componentMap: std.AutoHashMapUnmanaged(ComponentType, u32),

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        for (self.componentArrays.items) |*array| array.deinit(array, allocator);
        self.componentArrays.deinit(allocator);
        self.entityToRowMap.deinit(allocator);
        self.rowToEntityMap.deinit(allocator);
        self.componentMap.deinit(allocator);
    }
};
