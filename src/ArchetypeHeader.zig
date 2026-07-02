const std = @import("std");

ptr: [*]u8,

const Self = @This();

pub fn entities_offset(self: *Self) *u32 {
    return @ptrCast(@alignCast(self.ptr));
}

pub fn component_offset(self: *Self) *u32 {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32)));
}

pub fn count(self: *Self) *u32 {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32) * 2));
}

pub fn capacity(self: *Self) *u32 {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32) * 3));
}

pub fn component_bitset(self: *Self) *std.bit_set.IntegerBitSet(128) {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32) * 4));
}

pub fn tag_bitset(self: *Self) *std.bit_set.IntegerBitSet(128) {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32) * 4 + @sizeOf(u128)));
}

pub fn size() comptime_int {
    return @sizeOf(u32) * 4 + @sizeOf(u128) * 2;
}

pub fn alignment() comptime_int {
    return @alignOf(u128);
}
