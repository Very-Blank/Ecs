const std = @import("std");

pub fn getTuple(comptime T: type) std.builtin.Type.Struct {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given a struct. Expected a tuple.");
            return @"struct";
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn getTupleAllowEmpty(comptime T: type) std.builtin.Type.Struct {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple and @"struct".fields.len != 0) @compileError("Unexpected type, was given a struct. Expected a tuple.");
            return @"struct";
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn getStruct(comptime T: type) std.builtin.Type.Struct {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given a tuple. Expected a struct.");
            return @"struct";
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn compileErrorIfZSTInStruct(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            inline for (@"struct".fields) |field| {
                if (@sizeOf(field.type) == 0) {
                    @compileError("Struct has a ZST.");
                }
            }
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn getFn(comptime T: type, name: []const u8) std.builtin.Type.Fn {
    if (@hasDecl(T, name)) {
        switch (@typeInfo(@TypeOf(@field(T, name)))) {
            .@"fn" => |@"fn"| return @"fn",
            else => {},
        }
    }

    @compileError("Unexpected type, was given " ++ @typeName(T) ++ " and it didn't have a fn " ++ name ++ " as expected");
}

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

pub fn TupleOfArrayLists(comptime T: type) type {
    const tuple: std.builtin.Type.Struct = getTuple(T);
    var newFields: [tuple.fields.len]std.builtin.Type.StructField = init: {
        var newFields: [tuple.fields.len]std.builtin.Type.StructField = undefined;
        for (tuple.fields, 0..) |field, i| {
            if (@sizeOf(field.type) == 0) @compileError("Tuple of arraylists can't store a ZST, was given type " ++ @typeName(field.type) ++ ".");
            newFields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = std.ArrayListUnmanaged(field.type),
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(std.ArrayListUnmanaged(field.type)),
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

pub fn TupleOfBuffers(comptime T: type) type {
    const tuple = getTuple(T);
    const newFields: [tuple.fields.len]std.builtin.Type.StructField = init: {
        var newFields: [tuple.fields.len]std.builtin.Type.StructField = undefined;

        for (tuple.fields, 0..) |field, i| {
            if (@sizeOf(field.type) == 0) @compileError("Tuple of buffers can't store a ZST, was given type " ++ @typeName(field.type) ++ ".");
            newFields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = [][]field.type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf([][]field.type),
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

pub fn TupleOfComponents(comptime T: type) type {
    const tuple = getTuple(T);
    const newFields: [tuple.fields.len]std.builtin.Type.StructField = init: {
        var newFields: [tuple.fields.len]std.builtin.Type.StructField = undefined;
        for (tuple.fields, 0..) |field, i| {
            if (@sizeOf(field.type) == 0) @compileError("Tuple of components can't store a ZST, was given type " ++ @typeName(field.type) ++ ".");
            newFields[i] = std.builtin.Type.StructField{
                .name = itoa(i),
                .type = *field.type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(*field.type),
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
