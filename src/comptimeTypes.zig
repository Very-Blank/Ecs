const std = @import("std");

pub fn itoa(comptime value: anytype) [:0]const u8 {
    comptime var string: [:0]const u8 = "";
    comptime var num = value;

    if (num == 0) {
        string = string ++ .{'0'};
    } else {
        while (num != 0) {
            string = string ++ .{'0' + (num % 10)};
            num = num / 10;
        }
    }

    return string;
}

pub fn TupleOfArrayLists(components: []const type) type {
    var new_fields: [components.len]std.builtin.Type.StructField = init: {
        var new_fields: [components.len]std.builtin.Type.StructField = undefined;
        for (components, 0..) |component, i| {
            if (@sizeOf(component) == 0) @compileError("Tuple of arraylists can't store a ZST, was given type " ++ @typeName(component) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = std.ArrayListUnmanaged(component),
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(std.ArrayListUnmanaged(component)),
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleOfSliceArrayLists(components: []const type) type {
    var new_fields: [components.len]std.builtin.Type.StructField = init: {
        var new_fields: [components.len]std.builtin.Type.StructField = undefined;
        for (components, 0..) |component, i| {
            if (@sizeOf(component) == 0) @compileError("Tuple of arraylists can't store a ZST, was given type " ++ @typeName(component) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = std.ArrayListUnmanaged([]component),
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(std.ArrayListUnmanaged([]component)),
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleOfItems(items: []const type) type {
    const new_fields: [items.len]std.builtin.Type.StructField = init: {
        var new_fields: [items.len]std.builtin.Type.StructField = undefined;
        for (items, 0..) |component, i| {
            if (@sizeOf(component) == 0) @compileError("Tuple of components can't store a ZST, was given type " ++ @typeName(component) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = component,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(component),
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleOfBuffers(components: []const type) type {
    const new_fields: [components.len]std.builtin.Type.StructField = init: {
        var new_fields: [components.len]std.builtin.Type.StructField = undefined;

        for (components, 0..) |component, i| {
            if (@sizeOf(component) == 0) @compileError("Tuple of buffers can't store a ZST, was given type " ++ @typeName(component) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = [][]component,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf([][]component),
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleOfItemsArrays(items: []const type) type {
    var new_fields: [items.len]std.builtin.Type.StructField = init: {
        var new_fields: [items.len]std.builtin.Type.StructField = undefined;
        for (items, 0..) |item, i| {
            if (@sizeOf(item) == 0) @compileError("Tuple of item arrays can't store a ZST, was given type " ++ @typeName(item) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = []item,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = []item,
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn TupleOfItemPtrs(items: []const type) type {
    const new_fields: [items.len]std.builtin.Type.StructField = init: {
        var new_fields: [items.len]std.builtin.Type.StructField = undefined;

        for (items, 0..) |component, i| {
            if (@sizeOf(component) == 0) @compileError("Tuple of buffers can't store a ZST, was given type " ++ @typeName(component) ++ ".");
            new_fields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = *component,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(*component),
            };
        }

        break :init new_fields;
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}
