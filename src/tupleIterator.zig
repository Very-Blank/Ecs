const std = @import("std");
const help = @import("help.zig");

const TupleOfBuffers = help.TupleOfBuffers;
const TupleOfItemPtrs = help.TupleOfItemPtrs;

const EntityID = @import("ecs.zig").EntityID;

pub fn GenericTupleIterator(comptime components: []const type, comptime size: usize) type {
    return struct {
        tuple_of_arrays: TupleOfBuffers(components, size),
        entities: [size][]const EntityID,
        count: u32,

        index: u32,
        array: u32,

        const Self = @This();

        pub fn init(tuple_of_arrays: TupleOfBuffers(components, size), ids: [size][]const EntityID, count: u32) Self {
            return .{
                .tuple_of_arrays = tuple_of_arrays,
                .entities = ids,
                .count = count,

                .index = 0,
                .array = 0,
            };
        }

        pub fn reset(self: *Self) void {
            self.array = 0;
            self.index = 0;
        }

        /// Returns the next value in the iterated arrays, if one doesn't exist returns null.
        pub fn next(self: *Self) ?TupleOfItemPtrs(components) {
            if (self.count <= self.array) {
                return null;
            }

            var value: TupleOfItemPtrs(components) = undefined;
            inline for (0..components.len) |i| {
                value[i] = &self.tuple_of_arrays[i][self.array][self.index];
            }

            if (self.index + 1 < self.tuple_of_arrays[0][self.array].len) {
                self.index += 1;

                return value;
            }

            self.array += 1;
            self.index = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.array < self.count;
        }

        /// Returns the entity's id that owns the component that was returned in the next() call.
        pub fn entity(self: Self) EntityID {
            if (self.index == 0) {
                if (0 < self.array)
                    return self.arrays[self.array - 1][self.arrays[self.array - 1].len - 1];

                return self.ids[0][0];
            }

            return self.arrays[self.array][self.index - 1];
        }
    };
}
