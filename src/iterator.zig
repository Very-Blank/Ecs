const std = @import("std");
const EntityID = @import("ecs.zig").EntityID;

// FIXME:
pub fn GenericIterator(comptime T: type, comptime size: usize) type {
    if (size == 0)
        @compileError(std.fmt.comptimePrint("Unexpected size: {d}, expected a size greater than zero.", .{size}));

    return struct {
        arrays: [size][]T,
        ids: [size][]const EntityID,
        count: u32,

        index: u32,
        array: u32,

        const Self = @This();

        pub fn init(arrays: [size][]T, ids: [size][]const EntityID, count: u32) Self {
            std.debug.assert(0 < count);

            for (arrays[0..count]) |array| {
                std.debug.assert(0 < array.len);
            }

            return .{
                .arrays = arrays,
                .ids = ids,
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
        pub fn next(self: *Self) ?*T {
            if (self.count <= self.array) {
                return null;
            }

            const value: *T = &self.arrays[self.array][self.index];

            if (self.index + 1 < self.arrays[self.array].len) {
                self.index += 1;

                return value;
            }

            self.array += 1;
            self.index = 0;

            return value;
        }

        pub fn isNext(self: Self) bool {
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
