const std = @import("std");
const typeId = @import("typeId.zig");

const INITIALIZE_SIZE = 8;

pub const ComponentList = struct {
    //THIS SHOULD BE ELSE WHERE!
    size: usize, // Size of component type in bytes
    alignment: usize, // Alignment requirement
    typeId: typeId.TypeId, // Unique type identifier
    // ------------------------

    len: u64,
    buffer: []u8,

    allocator: std.mem.Allocator,

    pub fn init(comptime T: type, allocator: std.mem.Allocator) !ComponentList {
        const size = @sizeOf(T);
        const alignment = @alignOf(T);

        return .{
            .size = size,
            .alignment = alignment,
            .typeId = typeId.get(T),
            .len = 0,
            .buffer = try allocator.alloc(u8, (size + alignment) * INITIALIZE_SIZE),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentList) void {
        self.allocator.free(self.buffer);
    }

    pub fn append(self: *ComponentList, comptime T: type, value: T) !void {
        std.debug.assert(typeId.get(T) == self.typeId);

        const cSize = self.size + self.alignment;
        const bytes: [@sizeOf(T)]u8 = @as(*[@sizeOf(T)]u8, @ptrCast(@alignCast(@constCast(&value)))).*;

        if (self.len + 1 < self.buffer.len / cSize) {
            @memcpy(self.buffer[cSize * self.len .. cSize * (self.len + 1) - self.alignment], &bytes);
            self.len += 1;
        } else {
            const buffer = try self.allocator.alloc(u8, self.len * 2);
            @memcpy(self.buffer, buffer[0..self.len]);
            self.buffer = buffer;

            @memcpy(self.buffer[cSize * self.len .. cSize * (self.len + 1) - self.alignment], &bytes);
            self.len += 1;
        }
    }

    pub fn remove(self: *ComponentList, i: u64) void {
        std.debug.assert(i < self.len);

        for (i..self.len - 1) |j| {
            const target = (self.size + self.alignment) * j;
            const mover = (self.size + self.alignment) * (j + 1);

            for (0..self.size) |k| {
                self.buffer[target + k] = self.buffer[mover + k];
            }
        }

        self.len -= 1;
    }

    pub fn get(self: *ComponentList, comptime T: type, i: u64) *T {
        std.debug.assert(i < self.len);
        std.debug.assert(typeId.get(T) == self.typeId);

        return @ptrCast(@alignCast(&self.buffer[(self.size + self.alignment) * i]));
    }
};
