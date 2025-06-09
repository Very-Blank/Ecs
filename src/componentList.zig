const std = @import("std");
const typeId = @import("typeId.zig");

const INITIALIZE_SIZE = 8;

pub const ComponentList = struct {
    componentSize: usize, // Size of component type in bytes
    componentAlignment: usize, // Alignment requirement
    typeId: typeId.TypeId, // Unique type identifier

    size: u64,
    buffer: []u8,

    allocator: std.mem.Allocator,

    pub fn init(comptime T: type, allocator: std.mem.Allocator) !ComponentList {
        const size = @sizeOf(T);
        const alignment = @alignOf(T);

        return .{
            .componentSize = size,
            .componentAlignment = alignment,
            .typeId = typeId.get(),
            .size = 0,
            .buffer = try allocator.alloc(u8, (size + alignment) * INITIALIZE_SIZE),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentList) void {
        self.allocator.free(self.buffer);
    }

    pub fn append(self: *ComponentList, comptime T: type, value: T) !void {
        std.debug.assert(typeId.get(T) == self.typeId);

        const cSize = self.componentSize + self.componentAlignment;
        const bytes: [@sizeOf(T)]u8 = @as([@sizeOf(T)]u8, @ptrCast(@alignCast(&value))).*;

        if (self.size + 1 < self.buffer.len / cSize) {
            @memcpy(self.buffer[cSize * self.size .. cSize * (self.size + 1)], bytes);
            self.size += 1;
        } else {
            const buffer = try self.allocator.alloc(u8, self.size * 2);
            @memcpy(self.buffer, buffer[0..self.size]);
            self.buffer = buffer;

            @memcpy(self.buffer[cSize * self.size .. cSize * (self.size + 1)], bytes);
            self.size += 1;
        }
    }

    pub fn remove(self: *ComponentList, i: u64) void {
        std.debug.assert(i < self.size);

        for (i..self.size - 1) |j| {
            const target = (self.componentSize + self.componentAlignment) * j;
            const mover = (self.componentSize + self.componentAlignment) * j + 1;

            for (0..self.componentSize) |k| {
                self.buffer[target + k] = self.buffer[mover + k];
            }
        }

        self.size -= 1;
    }

    pub fn get(self: *ComponentList, comptime T: type, i: u64) T {
        std.debug.assert(i < self.size);
        std.debug.assert(typeId.get(T) == self.typeId);

        return @ptrCast(@alignCast(self.buffer[(self.componentSize + self.componentAlignment) * i]));
    }
};
