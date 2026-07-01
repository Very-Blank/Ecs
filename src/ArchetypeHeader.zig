const std = @import("std");

entities_offset: u32,
component_offset: u32,
count: u32,
capacity: u32,

component_bitset: std.bit_set.IntegerBitSet(128),
tag_bitset: std.bit_set.IntegerBitSet(128),

const Self = @This();
