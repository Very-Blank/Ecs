const std = @import("std");
const help = @import("help.zig");

erased: []*anyopaque,
capacity: usize,
count: usize,

init_capacity: usize = 1,

deinit: *const fn (self: *Self, allocator: std.mem.Allocator) void,
remove: *const fn (self: *Self, index: usize, allocator: std.mem.Allocator) void,

const Self = @This();

pub fn init(comptime items: []const type) Self {
    return .{
        .erased = undefined,
        .capacity = 0,
        .count = 0,
        .init_capacity = init: {
            var min_init_capacity: usize = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
            if (min_init_capacity == 1) break :init min_init_capacity;

            inline for (1..items.len) |i| {
                if (@max(1, std.atomic.cache_line / @sizeOf(items[i])) < min_init_capacity) {
                    min_init_capacity = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
                    if (min_init_capacity == 1) break :init min_init_capacity;
                }
            }

            break :init min_init_capacity;
        },
        .remove = struct {
            pub fn remove(self: *Self, index: usize, _allocator: std.mem.Allocator) void {
                inline for (items, 0..) |T, j| {
                    const unerased: [*]T = @ptrCast(@alignCast(self.erased[j]));
                    help.callDeinit(T, &unerased[index], _allocator);

                    if (index != self.count - 1) {
                        unerased[index] = unerased[self.count - 1];
                    }
                }

                self.count -= 1;
            }
        }.remove,
        .deinit = struct {
            pub fn deinit(self: *Self, _allocator: std.mem.Allocator) void {
                if (0 < self.capacity) {
                    inline for (items, 0..) |T, i| {
                        const unerased: [*]T = @ptrCast(@alignCast(self.erased[i]));

                        for (unerased[0..self.count]) |*item| {
                            help.callDeinit(T, item, _allocator);
                        }

                        _allocator.free(unerased[0..self.capacity]);
                    }
                }

                _allocator.free(self.erased);

                self.capacity = 0;
                self.count = 0;
            }
        }.deinit,
    };
}

inline fn growCapacity(self: *Self) usize {
    var new = self.capacity;

    while (true) {
        new +|= new / 2 + self.init_capacity;
        if (new >= self.capacity + 1)
            return new;
    }
}

// FIXME:  If allocation fails we must deallocated.
pub fn append(
    self: *Self,
    comptime items: []const type,
    row: @Tuple(items),
    allocator: std.mem.Allocator,
) !void {
    if (self.capacity == 0) {
        const new_arrays: []*anyopaque = try allocator.alloc(*anyopaque, items.len);
        errdefer allocator.free(new_arrays);

        inline for (items, 0..) |T, i| {
            new_arrays[i] = @as(*anyopaque, @ptrCast((allocator.alloc(T, self.init_capacity) catch |err| {
                inline for (0..i) |j| {
                    allocator.free(@as([*]items[j], @ptrCast(@alignCast(new_arrays[j])))[0..self.init_capacity]);
                }

                return err;
            }).ptr));
        }

        allocator.free(self.erased);

        self.erased = new_arrays;
        self.capacity = self.init_capacity;
    } else if (self.capacity < self.count + 1) {
        const new_capacity = self.growCapacity();

        const new_arrays: []*anyopaque = try allocator.alloc(*anyopaque, items.len);
        errdefer allocator.free(new_arrays);

        inline for (items, 0..) |T, i| {
            new_arrays[i] = @as(*anyopaque, @ptrCast((allocator.alloc(T, new_capacity) catch |err| {
                inline for (0..i) |j| {
                    allocator.free(@as([*]items[j], @ptrCast(@alignCast(new_arrays[j])))[0..new_capacity]);
                }

                return err;
            }).ptr));
        }

        inline for (items, 0..) |T, i| {
            @memcpy(@as([*]T, @ptrCast(@alignCast(new_arrays[i])))[0..self.capacity], @as([*]T, @ptrCast(@alignCast(self.erased[i])))[0..self.capacity]);
            allocator.free(@as([*]T, @ptrCast(@alignCast(self.erased[i])))[0..self.capacity]);
        }

        allocator.free(self.erased);

        self.erased = new_arrays;
        self.capacity = new_capacity;
    }

    inline for (items, 0..) |T, i| {
        @as([*]T, @ptrCast(@alignCast(self.erased[i])))[self.count] = row[i];
    }

    self.count += 1;

    return;
}

pub fn swapRemove(self: *Self, comptime items: []const type, i: usize) @Tuple(items) {
    std.debug.assert(i < self.count);

    var tuple_of_items: @Tuple(items) = undefined;

    inline for (items, 0..) |T, j| {
        tuple_of_items[j] = @as([*]T, @ptrCast(self.erased[j]))[i];
    }

    if (i != self.count - 1) {
        inline for (items, 0..) |T, j| {
            @as([*]T, @ptrCast(self.erased[j]))[i] = @as([*]T, @ptrCast(self.erased[j]))[self.count - 1];
        }
    }

    self.count -= 1;

    return tuple_of_items;
}

pub fn getItemArray(self: *Self, index: usize, item: type) []item {
    std.debug.assert(0 < self.count);
    return @as([*]item, @ptrCast(@alignCast(self.erased[index])))[0..self.count];
}
