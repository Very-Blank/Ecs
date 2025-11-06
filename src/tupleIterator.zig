const std = @import("std");
const TupleOfBuffers = @import("comptimeTypes.zig").TupleOfBuffers;
const TupleOfComponentPtrs = @import("comptimeTypes.zig").TupleOfItemPtrs;
const EntityPointer = @import("ecs.zig").EntityPointer;

pub fn TupleIterator(comptime components: []const type) type {
    return struct {
        tuple_of_buffers: TupleOfBuffers(components),
        entities: []const []const EntityPointer,
        current_entity: EntityPointer,
        current_index: u32,
        current_buffer: u32,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(tupleOfBuffers: TupleOfBuffers(components), entities: []const []const EntityPointer, allocator: std.mem.Allocator) Self {
            std.debug.assert(tupleOfBuffers.len > 0);
            inline for (0..components.len) |i| {
                std.debug.assert(tupleOfBuffers[i].len > 0);
                std.debug.assert(tupleOfBuffers[i][0].len > 0);
            }

            return .{
                .tuple_of_buffers = tupleOfBuffers,
                .entities = entities,
                .current_entity = entities[0][0],
                .current_index = 0,
                .current_buffer = 0,
                .allocator = allocator,
            };
        }

        // Frees the array that holds the buffers, doesn't touch the actual buffers.
        pub fn deinit(self: *Self) void {
            inline for (0..components.len) |i| {
                self.allocator.free(self.tuple_of_buffers[i]);
            }

            self.tuple_of_buffers = undefined;

            self.allocator.free(self.entities);
            self.entities = undefined;
        }

        pub fn reset(self: *Self) void {
            self.current_buffer = 0;
            self.current_index = 0;
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) ?TupleOfComponentPtrs(components) {
            if (self.tuple_of_buffers[0].len <= self.current_buffer) {
                return null;
            }

            var value: TupleOfComponentPtrs(components) = undefined;
            inline for (0..components.len) |i| {
                value[i] = &self.tuple_of_buffers[i][self.current_buffer][self.current_index];
                self.current_entity = self.entities[self.current_buffer][self.current_index];
            }

            if (self.current_index + 1 < self.tuple_of_buffers[0][self.current_buffer].len) {
                self.current_index += 1;

                return value;
            }

            self.current_buffer += 1;
            self.current_index = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.current_buffer < self.tuple_of_buffers[0].len;
        }

        /// Returns current entity for components that where called with the last next()
        /// If next() return null and this is called this returns the last valid entity.
        pub fn getCurrentEntity(self: *Self) EntityPointer {
            return self.current_entity;
        }
    };
}
