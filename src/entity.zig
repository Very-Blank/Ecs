const std = @import("std");

pub const Entity = enum(u32) {
    invalid = 0,
    _,

    pub inline fn make(@"u32": u32) Entity {
        std.debug.assert(@"u32" != 0);
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": Entity) u32 {
        std.debug.assert(@"enum" != .invalid);
        return @intFromEnum(@"enum");
    }
};

pub const Unused = enum(u32) { _ };

pub const Row = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) Row {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": Row) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const ArchetypeId = enum(u16) {
    _,

    pub inline fn make(@"u16": u16) Row {
        return @enumFromInt(@"u16");
    }

    pub inline fn value(@"enum": Row) u16 {
        return @intFromEnum(@"enum");
    }
};

pub const Pointer = struct {
    row: Row,
    archetype: ArchetypeId,
};
