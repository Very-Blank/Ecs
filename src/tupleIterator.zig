const std = @import("std");
const TupleOfBuffers = @import("comptimeTypes.zig").TupleOfBuffers;
const TupleOfComponentPtrs = @import("comptimeTypes.zig").TupleOfComponentPtrs;
const EntityType = @import("ecs.zig").EntityType;

pub fn TupleIterator(comptime components: []const type) type {
    return struct {
        tupleOfBuffers: TupleOfBuffers(components),
        entities: []const []const EntityType,
        currentEntity: EntityType,
        currentIndex: u32,
        currentBuffer: u32,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(tupleOfBuffers: TupleOfBuffers(components), entities: []const []const EntityType, allocator: std.mem.Allocator) Self {
            std.debug.assert(tupleOfBuffers.len > 0);
            inline for (0..components.len) |i| {
                std.debug.assert(tupleOfBuffers[i].len > 0);
                std.debug.assert(tupleOfBuffers[i][0].len > 0);
            }

            return .{
                .tupleOfBuffers = tupleOfBuffers,
                .entities = entities,
                .currentEntity = entities[0][0],
                .currentIndex = 0,
                .currentBuffer = 0,
                .allocator = allocator,
            };
        }

        // Frees the array that holds the buffers, doesn't touch the actual buffers.
        pub fn deinit(self: *Self) void {
            inline for (0..components.len) |i| {
                self.allocator.free(self.tupleOfBuffers[i]);
            }

            self.tupleOfBuffers = undefined;

            self.allocator.free(self.entities);
            self.entities = undefined;
        }

        pub fn reset(self: *Self) void {
            self.currentBuffer = 0;
            self.currentIndex = 0;
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) ?TupleOfComponentPtrs(components) {
            if (self.tupleOfBuffers[0].len <= self.currentBuffer) {
                return null;
            }

            var value: TupleOfComponentPtrs(components) = undefined;
            inline for (0..components.len) |i| {
                value[i] = &self.tupleOfBuffers[i][self.currentBuffer][self.currentIndex];
                self.currentEntity = self.entities[self.currentBuffer][self.currentIndex];
            }

            if (self.currentIndex + 1 < self.tupleOfBuffers[0][self.currentBuffer].len) {
                self.currentIndex += 1;

                return value;
            }

            self.currentBuffer += 1;
            self.currentIndex = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.currentBuffer < self.tupleOfBuffers[0].len;
        }

        /// Returns current entity for components that where called with the last next()
        /// If next() return null and this is called this returns the last valid entity.
        pub fn getCurrentEntity(self: *Self) EntityType {
            return self.currentEntity;
        }
    };
}
