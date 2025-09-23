const std = @import("std");
const compTypes = @import("comptimeTypes.zig");

pub fn TupleOfManyPointers(items: []const type) type {
    var newFields: [items.len]std.builtin.Type.StructField = init: {
        var newFields: [items.len]std.builtin.Type.StructField = undefined;
        for (items, 0..) |item, i| {
            if (@sizeOf(item) == 0) @compileError("Tuple of many pointers can't store a ZST, was given type " ++ @typeName(item) ++ ".");
            newFields[i] = std.builtin.Type.StructField{
                .name = compTypes.itoa(i),
                .type = [*]item,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = [*]item,
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

        const empty: Self = Self{
            .tupleOfManyPointers = init: {
                const tupleOfManyPointers: @FieldType(Self, "tupleOfManyPointers") = undefined;
                for (0..items.len) |i| {
                    tupleOfManyPointers[i] = undefined;
                }

                break :init tupleOfManyPointers;
            },
            .capacity = 0,
            .count = 0,
        };

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
            item: compTypes.TupleOfComponents(items),
            allocator: std.mem.Allocator,
        ) !void {
            if (self.capacity < self.count + 1) {
                const newCapacity = growCapacity(self.capacity, self.capacity + 1);
                inline for (items, 0..) |T, i| {
                    const oldArray = self.tupleOfManyPointers[i][0..self.capacity];
                    const newArray = try allocator.alloc(T, newCapacity);
                    @memcpy(newArray[0..self.capacity], oldArray);
                    newArray[self.capacity + 1] = item[i];

                    allocator.free(oldArray);

                    self.tupleOfManyPointers[i] = &newArray;
                }
            }
        }

        pub fn swapRemove(self: *Self, i: usize) compTypes.TupleOfItems(items) {}

        pub fn getItemsArrays(self: *Self) compTypes.TupleOfItemsArrays(items) {}

        pub fn getItemArray(self: *Self, item: type) []item {}
    };
}
