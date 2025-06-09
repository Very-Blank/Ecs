const std = @import("std");
const typeId = @import("typeId.zig").typeId;
const Component = @import("component.zig").Component;

const INITIALIZE_SIZE = 8;

pub const ComponentBuffer = struct {
    componentId: u32,
    buffer: []u8,
    len: u64,

    allocator: std.mem.Allocator,

    pub fn init(componentId: u32, component: Component, allocator: std.mem.Allocator) !ComponentBuffer {
        return .{
            .componentId = componentId,
            .buffer = try allocator.alloc(u8, (component.size + component.alignment) * INITIALIZE_SIZE),
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentBuffer) void {
        self.allocator.free(self.buffer);
    }

    pub fn append(self: *ComponentBuffer, component: Component, comptime T: type, value: T) !void {
        const cSize = component.size + component.alignment;
        const bytes: [@sizeOf(T)]u8 = @as(*[@sizeOf(T)]u8, @ptrCast(@alignCast(@constCast(&value)))).*;

        if (self.len + 1 < self.buffer.len / cSize) {
            @memcpy(self.buffer[cSize * self.len .. cSize * (self.len + 1) - component.alignment], &bytes);
            self.len += 1;
        } else {
            const buffer = try self.allocator.alloc(u8, self.len * 2);
            @memcpy(self.buffer, buffer[0..self.len]);
            self.buffer = buffer;

            @memcpy(self.buffer[cSize * self.len .. cSize * (self.len + 1) - component.alignment], &bytes);
            self.len += 1;
        }
    }

    pub fn remove(self: *ComponentBuffer, component: Component, i: u64) void {
        std.debug.assert(i < self.len);

        for (i..self.len - 1) |j| {
            const target = (component.size + component.alignment) * j;
            const mover = (component.size + component.alignment) * (j + 1);

            for (0..self.size) |k| {
                self.buffer[target + k] = self.buffer[mover + k];
            }
        }

        self.len -= 1;
    }

    pub fn get(self: *ComponentBuffer, component: Component, comptime T: type, i: u64) *T {
        std.debug.assert(i < self.len);

        return @ptrCast(@alignCast(&self.buffer[(component.size + component.alignment) * i]));
    }
};
