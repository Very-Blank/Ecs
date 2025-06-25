const std = @import("std");

pub fn EventManager(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (!info.is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or it was a tuple, but was empty");

            inline for();

        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}
