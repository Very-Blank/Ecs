const std = @import("std");

pub fn TupleOfItems(items: []const type) type {
    if (items.len == 0) @compileError("TypeOfItems can't be empty.");

    for (items) |item|
        if (@sizeOf(item) == 0) @compileError("Tuple of buffers can't store a ZST, was given type " ++ @typeName(item) ++ ".");

    return @Tuple(items);
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
