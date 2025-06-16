const std = @import("std");

pub fn Iterator(comptime T: type) !type {
    return struct {
        buffers: [][]T,
        currentIndex: u32,
        currentBuffer: u32,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(buffers: [][]T) Self {
            return .{
                .buffers = buffers,
                .currentIndex = 0,
                .currentBuffer = 0,
            };
        }

        // Frees the array that holds the buffers, doesn't touch the actual buffers.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffers);
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) .{ T, bool } {
            const value = self.buffers[self.currentBuffer][self.currentIndex];

            if (self.currentIndex + 1 < self.buffers[self.currentBuffer].len) {
                self.currentIndex += 1;

                return .{ value, true };
            } else if (self.currentBuffer + 1 < self.buffers.len) {
                self.currentBuffer += 1;
                self.currentIndex = 0;

                return .{ value, true };
            }

            return .{ value, false };
        }
    };
}
