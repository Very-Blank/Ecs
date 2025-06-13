const std = @import("std");

pub const Entity = struct { pointerId: IndexType, generation: GenerationType };

pub const IndexType = enum(u16) {
    _,

    pub inline fn make(@"u32": u16) IndexType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": IndexType) u16 {
        return @intFromEnum(@"enum");
    }
};

pub const ArchetypeType = enum(u8) {
    _,

    pub inline fn make(@"u8": u8) ArchetypeType {
        return @enumFromInt(@"u8");
    }

    pub inline fn value(@"enum": ArchetypeType) u8 {
        return @intFromEnum(@"enum");
    }
};

const GenerationType = enum(u8) {
    _,

    pub inline fn make(@"u8": u8) GenerationType {
        return @enumFromInt(@"u8");
    }

    pub inline fn value(@"enum": GenerationType) u8 {
        return @intFromEnum(@"enum");
    }
};

pub const Pointer = struct {
    rowId: IndexType,
    generation: GenerationType,
    archetype: ArchetypeType,
};
