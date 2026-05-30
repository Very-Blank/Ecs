const std = @import("std");

pub fn callDeinit(comptime T: type, item: *T, allocator: std.mem.Allocator) void {
    const deinit_fn = init: {
        switch (@typeInfo(T)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => {},
            else => return,
        }

        if (!@hasDecl(T, "deinit")) return;

        switch (@typeInfo(@TypeOf(T.deinit))) {
            .@"fn" => |deinit_fn| break :init deinit_fn,
            else => return,
        }
    };

    if (0 < deinit_fn.params.len) {
        const parameter1: type = deinit_fn.params[0].type orelse T;

        switch (@typeInfo(parameter1)) {
            .pointer => |pointer| if (pointer.child != T) return,
            else => return,
        }

        if (deinit_fn.params.len == 1) {
            item.deinit();
        } else if (deinit_fn.params.len == 2 and
            (deinit_fn.params[1].type orelse return) == std.mem.Allocator)
        {
            item.deinit(allocator);
        }
    }
}

pub fn TupleOfBuffers(items: []const type, buffer_len: usize) type {
    if (items.len == 0) @compileError("TupleOfBuffers can't be empty.");

    return @Tuple(
        init_types: {
            var new_types: [items.len]type = undefined;

            for (items, 0..) |item, i| {
                if (@sizeOf(item) == 0) @compileError("Tuple of buffers can't store a ZST, was given type " ++ @typeName(item) ++ ".");
                new_types[i] = [buffer_len][]item;
            }

            break :init_types &new_types;
        },
    );
}

fn TupleOfManyPointers(items: []const type) type {
    return @Tuple(init_types: {
        var new_items: [items.len]type = undefined;

        for (items, 0..) |item, i| {
            if (@sizeOf(item) == 0) @compileError("Tuple of many pointers can't store a ZST, was given type " ++ @typeName(item) ++ ".");
            new_items[i] = [*]item;
        }

        break :init_types &new_items;
    });
}

pub fn TupleOfItemsArrays(items: []const type) type {
    if (items.len == 0) @compileError("TupleOfItemsArrays can't be empty.");

    return @Tuple(
        init_types: {
            var new_types: [items.len]type = undefined;

            for (items, 0..) |item, i| {
                if (@sizeOf(item) == 0) @compileError("Tuple of item arrays can't store a ZST, was given type " ++ @typeName(item) ++ ".");
                new_types[i] = []item;
            }

            break :init_types &new_types;
        },
    );
}

pub fn TupleOfItemPtrs(items: []const type) type {
    return @Tuple(
        init_types: {
            var new_types: [items.len]type = undefined;

            for (items, 0..) |item, i| {
                if (@sizeOf(item) == 0) @compileError("Tuple of item arrays can't store a ZST, was given type " ++ @typeName(item) ++ ".");
                new_types[i] = *item;
            }

            break :init_types &new_types;
        },
    );
}
