const std = @import("std");

const Bitset = @import("componentManager.zig").Bitset;

pub const System = struct {
    handle: *anyopaque,
    update: *const fn (self: *System, List, deltaTime: f32) void,
    bitset: Bitset,

    // Register setups all of the things needed for the update to get called.
    // Maybe have func here that setups the list of Iterators since you know the type here.
    pub fn register(comptime: T, components: T, update etc..) System{}
};
