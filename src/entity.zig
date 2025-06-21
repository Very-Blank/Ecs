const std = @import("std");
const ArchetypeType = @import("archetype.zig").ArchetypeType;

pub const EntityType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) EntityType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": EntityType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const GenerationType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) GenerationType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": GenerationType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const SlimPointer = struct {
    entity: EntityType,
    generation: GenerationType,
};

pub const FatPointer = struct {
    archetype: ArchetypeType,
    generation: GenerationType,
};
