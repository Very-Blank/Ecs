ptr: [*]u8,

const Self = @This();

pub inline fn length(self: Self) *u32 {
    return @ptrCast(@alignCast(self.ptr));
}

pub inline fn entity_count(self: Self) *u32 {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32)));
}

pub inline fn entity_capacity(self: Self) *u32 {
    return @ptrCast(@alignCast(self.ptr + @sizeOf(u32) * 2));
}

pub inline fn size() comptime_int {
    return @sizeOf(u32) * 4;
}

pub inline fn alignment() comptime_int {
    return @alignOf(u32);
}
