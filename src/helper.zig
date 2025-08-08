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

pub fn getStruct(comptime T: type) std.builtin.Type.Struct {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given a tuple. Expected a struct.");
            return @"struct";
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

/// Removes all zero sized types from a tuple
fn removeZST(comptime T: type) type {
    const @"struct": std.builtin.Type.Struct = getTuple(T);
    var size: comptime_int = 0;
    inline for (@"struct".fields) |field| {
        if (@sizeOf(field.type) > 0) {
            size += 1;
        }
    }

    var new_fields: [size]std.builtin.Type.StructField = undefined;

    for (@"struct".fields, 0..) |field, i| {
        if (@sizeOf(field.type) > 0) {
            new_fields[i] = std.builtin.Type.StructField{
                .name = field.name,
                .type = field.type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(field.type),
            };
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
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
