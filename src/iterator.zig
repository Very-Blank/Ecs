const std = @import("std");
const EntityPointer = @import("ecs.zig").EntityPointer;

pub fn Iterator(comptime T: type, comptime size: usize) type {
    return struct {
        buffers: [size][]T,
        entities: [size][]const EntityPointer,
        buffer_len: u32,

        current_entity: EntityPointer,
        current_index: u32,
        current_buffer: u32,

        const Self = @This();

        pub fn init(buffers: [size][]T, entities: [size][]const EntityPointer, buffer_len: u32) Self {
            std.debug.assert(buffer_len > 0);
            for (0..buffer_len) |i| {
                std.debug.assert(buffers[i].len > 0);
            }

            return .{
                .buffers = buffers,
                .entities = entities,
                .buffer_len = buffer_len,
                .current_index = 0,
                .current_entity = entities[0][0],
                .current_buffer = 0,
            };
        }

        pub fn reset(self: *Self) void {
            self.current_buffer = 0;
            self.current_index = 0;
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) ?*T {
            if (self.buffer_len <= self.current_buffer) {
                return null;
            }

            const value: *T = &self.buffers[self.current_buffer][self.current_index];
            self.current_entity = self.entities[self.current_buffer][self.current_index];

            if (self.current_index + 1 < self.buffers[self.current_buffer].len) {
                self.current_index += 1;

                return value;
            }

            self.current_buffer += 1;
            self.current_index = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.current_buffer < self.buffer_len;
        }

        /// Returns current entity for components that where called with the last next()
        /// If next() return null and this is called this returns the last valid entity.
        pub fn getCurrentEntity(self: *Self) EntityPointer {
            return self.current_entity;
        }
    };
}
