const std = @import("std");

pub fn typesFromTuple(tuple: type) init_type: switch (@typeInfo(tuple)) {
    .@"struct" => |value| {
        if (!value.is_tuple or value.fields.len == 0) @compileError("Components must be in a non empty tuple.");
        break :init_type [value.fields.len]type;
    },
    else => @compileError("Was given " ++ @tagName(tuple) ++ ", expected a non empty tuple."),
} {
    const struct_info: std.builtin.Type.Struct = @typeInfo(tuple).@"struct";

    var components: [struct_info.fields.len]type = undefined;
    for (0..struct_info.fields.len) |i| {
        components[i] = struct_info.fields[i].type;
    }

    return components;
}

pub inline fn translateTuples(comptime current: []const type, current_tuple: @Tuple(current), comptime target: []const type) @Tuple(target) {
    if (current.len != target.len) @compileError("Was called with differing tuple sizes.");
    comptime order_check: {
        for (current, 0..) |current_type, i| {
            if (current_type != target[i]) break :order_check;
        }

        @compileError("Was given two tuples that had the same order.");
    }

    comptime outer: for (current) |current_type| {
        for (target) |target_type| {
            if (current_type == target_type) continue :outer;
        }

        @compileError("Was given two tuples that had different composition types.");
    };

    return init: {
        var new_components: @Tuple(target) = undefined;
        outer: inline for (target, 0..) |target_type, i| {
            inline for (current, 0..) |current_type, j| {
                if (target_type == current_type) {
                    new_components[i] = current_tuple[j];
                    continue :outer;
                }
            }
        }

        break :init new_components;
    };
}

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
