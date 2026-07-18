const std = @import("std");
const EntityPointer = @import("ecs.zig").EntityPointer;
const EntityID = @import("ecs.zig").EntityID;
const Generation = @import("ecs.zig").Generation;

// FIXME:
pub fn GenericIterator(comptime T: type, comptime size: usize) type {
    if (size == 0)
        @compileError(std.fmt.comptimePrint("Unexpected size: {d}, expected a size greater than zero.", .{size}));

    return struct {
        arrays: [size][]T,
        entity_ids: [size][]const EntityID,
        generations: []const Generation,
        len: u32,

        current_index: u32,
        current_array: u32,

        current_entity_id: EntityID,

        const Self = @This();

        pub fn init(arrays: [size][]T, entity_ids: [size][]const EntityID, generations: Generation, len: u32) Self {
            std.debug.assert(0 < len);
            for (arrays[0..len]) |array| {
                std.debug.assert(array.len);
            }

            return .{
                .arrays = arrays,
                .entity_ids = entity_ids,
                .generations = generations,
                .len = len,

                .current_index = 0,
                .current_entity_id = entity_ids[0][0],
                .current_array = 0,
            };
        }

        pub fn reset(self: *Self) void {
            self.current_array = 0;
            self.current_index = 0;
            self.current_entity_id = self.entity_ids[0][0];
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) ?*T {
            if (self.len <= self.current_array) {
                return null;
            }

            const value: *T = &self.arrays[self.current_array][self.current_index];
            self.current_entity_id = self.entity_ids[self.current_array][self.current_index];

            if (self.current_index + 1 < self.arrays[self.current_array].len) {
                self.current_index += 1;

                return value;
            }

            self.current_array += 1;
            self.current_index = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.current_array < self.len;
        }

        /// Returns current entity for components that where called with the last next()
        /// If next() return null and this is called this returns the last valid entity.
        pub fn currentEntity(self: *Self) EntityPointer {
            return .{.entity = self.current_array, .generation = self.generations[self.]};
        }
    };
}
