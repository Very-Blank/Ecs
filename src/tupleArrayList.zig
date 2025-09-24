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
        tupleOfManyPointers: TupleOfManyPointers(items),
        capacity: usize,
        count: usize,

        const Self = @This();

        /// Very similar what std does, but we want the largest component to determinate init capacity.
        const initCapacity: comptime_int = init: {
            var minInitCapacity = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
            if (minInitCapacity == 1) break :init minInitCapacity;

            for (1..items.len) |i| {
                if (@max(1, std.atomic.cache_line / @sizeOf(items[i])) < minInitCapacity) {
                    minInitCapacity = @max(1, std.atomic.cache_line / @sizeOf(items[0]));
                    if (minInitCapacity == 1) break :init minInitCapacity;
                }
            }

            break :init minInitCapacity;
        };

        pub const empty: Self = Self{
            .tupleOfManyPointers = init: {
                var tupleOfManyPointers: @FieldType(Self, "tupleOfManyPointers") = undefined;
                for (0..items.len) |i| {
                    tupleOfManyPointers[i] = undefined;
                }

                break :init tupleOfManyPointers;
            },
            .capacity = 0,
            .count = 0,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.capacity > 0) {
                inline for (0..items.len) |i| {
                    allocator.free(self.tupleOfManyPointers[i][0..self.capacity]);
                    self.tupleOfManyPointers[i] = undefined;
                }
            }

            self.capacity = 0;
            self.count = 0;
        }

        inline fn growCapacity(current: usize, minimum: usize) usize {
            var new = current;
            while (true) {
                new +|= new / 2 + initCapacity;
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
                const newCapacity = growCapacity(self.capacity, self.capacity + 1);

                inline for (items, 0..) |T, i| {
                    const newArray = allocator.alloc(T, newCapacity) catch |err| {
                        inline for (0..i) |j| {
                            allocator.free(self.tupleOfManyPointers[j][0..newCapacity]);
                            self.tupleOfManyPointers[j] = undefined;
                        }

                        return err;
                    };

                    self.tupleOfManyPointers[i] = newArray.ptr;
                }

                self.capacity = newCapacity;
            } else if (self.capacity < self.count + 1) {
                const newCapacity = growCapacity(self.capacity, self.capacity + 1);

                inline for (items, 0..) |T, i| {
                    const oldArray = self.tupleOfManyPointers[i][0..self.capacity];
                    const newArray = allocator.alloc(T, newCapacity) catch |err| {
                        inline for (0..i) |j| {
                            allocator.free(self.tupleOfManyPointers[j][0..newCapacity]);
                            self.tupleOfManyPointers[j] = undefined;
                        }

                        inline for (i..items.len) |j| {
                            allocator.free(self.tupleOfManyPointers[j][0..self.capacity]);
                            self.tupleOfManyPointers[j] = undefined;
                        }

                        return err;
                    };

                    @memcpy(newArray[0..self.capacity], oldArray);
                    allocator.free(oldArray);

                    self.tupleOfManyPointers[i] = newArray.ptr;
                }

                self.capacity = newCapacity;
            }

            inline for (0..items.len) |i| {
                self.tupleOfManyPointers[i][self.count] = item[i];
            }

            self.count += 1;
            return;
        }

        pub fn swapRemove(self: *Self, i: usize) compTypes.TupleOfItems(items) {
            std.debug.assert(i < self.count);

            var tupleOfItems: compTypes.TupleOfItems(items) = undefined;

            inline for (0..items.len) |j| {
                tupleOfItems[j] = self.tupleOfManyPointers[j][i];
            }

            if (i != self.count - 1) {
                inline for (0..items.len) |j| {
                    self.tupleOfManyPointers[j][i] = self.tupleOfManyPointers[j][self.count - 1];
                }
            }

            self.count -= 1;

            return tupleOfItems;
        }

        pub fn getItemsArrays(self: *Self) compTypes.TupleOfItemsArrays(items) {
            std.debug.assert(self.count > 0);

            var tupleOfItemArrays: compTypes.TupleOfItemsArrays(items) = undefined;

            inline for (0..items.len) |i| {
                tupleOfItemArrays[i] = self.tupleOfManyPointers[i][0..self.count];
            }

            return tupleOfItemArrays;
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

            return self.tupleOfManyPointers[index][0..self.count];
        }
    };
}
