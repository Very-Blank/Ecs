const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;
const ComponentType = @import("componentManager.zig").ComponentType;

const EntityType = @import("entity.zig").EntityType;
const ErasedArray = @import("erasedArray.zig").ErasedArray;

const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;

const Allocator = std.mem.Allocator;

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

pub const Archetype = struct {
    bitset: Bitset,
    componentArrays: std.ArrayListUnmanaged(ErasedArray),
    components: u32,

    entityToRowMap: std.AutoHashMapUnmanaged(EntityType, Row),
    rowToEntityMap: std.AutoHashMapUnmanaged(Row, EntityType),
    componentMap: std.AutoHashMapUnmanaged(ComponentType, u32),

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        for (self.componentArrays.items) |*array| array.deinit(array, allocator);
        self.componentArrays.deinit(allocator);
        self.entityToRowMap.deinit(allocator);
        self.rowToEntityMap.deinit(allocator);
        self.componentMap.deinit(allocator);
    }
};
