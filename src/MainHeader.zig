const std = @import("std");

ptr: [*]u8,

const Self = @This();

pub inline fn write(self: Self, values: struct {
    length: u32,
    entity_count: u32 = 0,
    entity_capacity: u32,
}) void {
    self.length().* = values.length;
    self.entity_count().* = values.entity_count;
    self.entity_capacity().* = values.entity_capacity;
}

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

pub fn Header(fields: []const u8, types: []const type) type {
    // TODO: assert no padding

    return struct {
        ptr: [*]u8,

        const S = @This();

        pub fn field(self: S, comptime name: []const u8) init: {
            for (fields, 0..) |capture, i|
                if (std.mem.eql(u8, name, capture)) break :init *types[i];

            @compileError("Field " ++ name ++ ", doesn't exist.");
        } {
            const offset: usize = comptime init: {
                var offset: comptime_int = 0;

                for (fields, 0..) |capture, i| {
                    if (std.mem.eql(u8, name, capture)) break :init offset;
                    offset += @sizeOf(types[i]);
                }

                @compileError("Field " ++ name ++ ", doesn't exist.");
            };

            return @ptrCast(@alignCast(self.ptr + offset));
        }

        // TODO: add size and aligment funcs.
    };
}
