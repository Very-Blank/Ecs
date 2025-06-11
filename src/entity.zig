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

pub const Pointer = struct {
    row: u32,
    archetype: u16,
};
