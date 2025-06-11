const std = @import("std");

pub const Pointer = struct {
    row: u32,
    archetype: u16,
    generation: u16,
};

pub const Entity = struct {
    id: u32,
    generation: u16,
};
