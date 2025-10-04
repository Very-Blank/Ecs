const std = @import("std");
const compTypes = @import("comptimeTypes.zig");

fn TupleOfManyPointers(items: []const type) type {
    var newFields: [items.len]std.builtin.Type.StructField = init: {
        var newFields: [items.len]std.builtin.Type.StructField = undefined;
        for (items, 0..) |item, i| {
            if (@sizeOf(item) == 0) @compileError("Tuple of many pointers can't store a ZST, was given type " ++ @typeName(item) ++ ".");
            newFields[i] = std.builtin.Type.StructField{
                .name = compTypes.itoa(i),
                .type = [*]item,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf([*]item),
            };
        }

        break :init newFields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &newFields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleArrayList(items: []const type) type {
    return struct {
        tuple_of_many_ptrs: TupleOfManyPointers(items),
        capacity: usize,
        count: usize,

        const Self = @This();

        /// Very similar what std does, but we want the largest component to determinate init capacity.
        const init_capacity: comptime_int = init: {
            var min_init_capacity = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
            if (min_init_capacity == 1) break :init min_init_capacity;

            for (1..items.len) |i| {
                if (@max(1, std.atomic.cache_line / @sizeOf(items[i])) < min_init_capacity) {
                    min_init_capacity = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
                    if (min_init_capacity == 1) break :init min_init_capacity;
                }
            }

            break :init min_init_capacity;
        };

        pub const empty: Self = Self{
            .tuple_of_many_ptrs = init: {
                var tuple_of_many_ptrs: @FieldType(Self, "tuple_of_many_ptrs") = undefined;
                for (0..items.len) |i| {
                    tuple_of_many_ptrs[i] = undefined;
                }

                break :init tuple_of_many_ptrs;
            },
            .capacity = 0,
            .count = 0,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.capacity > 0) {
                inline for (0..items.len) |i| {
                    allocator.free(self.tuple_of_many_ptrs[i][0..self.capacity]);
                    self.tuple_of_many_ptrs[i] = undefined;
                }
            }

            self.capacity = 0;
            self.count = 0;
        }

        inline fn growCapacity(current: usize, minimum: usize) usize {
            var new = current;
            while (true) {
                new +|= new / 2 + init_capacity;
                if (new >= minimum)
                    return new;
            }
        }

        // FIXME:  If allocation fails we must deallocated.
        pub fn append(
            self: *Self,
            item: compTypes.TupleOfItems(items),
            allocator: std.mem.Allocator,
        ) !void {
            if (self.capacity == 0) {
                const new_capacity = growCapacity(self.capacity, self.capacity + 1);

                inline for (items, 0..) |T, i| {
                    const new_array = allocator.alloc(T, new_capacity) catch |err| {
                        inline for (0..i) |j| {
                            allocator.free(self.tuple_of_many_ptrs[j][0..new_capacity]);
                            self.tuple_of_many_ptrs[j] = undefined;
                        }

                        return err;
                    };

                    self.tuple_of_many_ptrs[i] = new_array.ptr;
                }

                self.capacity = new_capacity;
            } else if (self.capacity < self.count + 1) {
                const new_capacity = growCapacity(self.capacity, self.capacity + 1);

                inline for (items, 0..) |T, i| {
                    const old_array = self.tuple_of_many_ptrs[i][0..self.capacity];
                    const new_array = allocator.alloc(T, new_capacity) catch |err| {
                        inline for (0..i) |j| {
                            allocator.free(self.tuple_of_many_ptrs[j][0..new_capacity]);
                            self.tuple_of_many_ptrs[j] = undefined;
                        }

                        inline for (i..items.len) |j| {
                            allocator.free(self.tuple_of_many_ptrs[j][0..self.capacity]);
                            self.tuple_of_many_ptrs[j] = undefined;
                        }

                        return err;
                    };

                    @memcpy(new_array[0..self.capacity], old_array);
                    allocator.free(old_array);

                    self.tuple_of_many_ptrs[i] = new_array.ptr;
                }

                self.capacity = new_capacity;
            }

            inline for (0..items.len) |i| {
                self.tuple_of_many_ptrs[i][self.count] = item[i];
            }

            self.count += 1;
            return;
        }

        pub fn swapRemove(self: *Self, i: usize) compTypes.TupleOfItems(items) {
            std.debug.assert(i < self.count);

            var tuple_of_items: compTypes.TupleOfItems(items) = undefined;

            inline for (0..items.len) |j| {
                tuple_of_items[j] = self.tuple_of_many_ptrs[j][i];
            }

            if (i != self.count - 1) {
                inline for (0..items.len) |j| {
                    self.tuple_of_many_ptrs[j][i] = self.tuple_of_many_ptrs[j][self.count - 1];
                }
            }

            self.count -= 1;

            return tuple_of_items;
        }

        pub fn getItemsArrays(self: *Self) compTypes.TupleOfItemsArrays(items) {
            std.debug.assert(self.count > 0);

            var tuple_of_item_arrays: compTypes.TupleOfItemsArrays(items) = undefined;

            inline for (0..items.len) |i| {
                tuple_of_item_arrays[i] = self.tuple_of_many_ptrs[i][0..self.count];
            }

            return tuple_of_item_arrays;
        }

        pub fn getItemArray(self: *Self, item: type) []item {
            std.debug.assert(self.count > 0);

            const index = comptime init: {
                for (items, 0..) |T, i| {
                    if (T == item) {
                        break :init i;
                    }
                }

                @compileError("TupleArrayList was given invalid type, " ++ @typeName(item) ++ ".");
            };

            return self.tuple_of_many_ptrs[index][0..self.count];
        }
    };
}
