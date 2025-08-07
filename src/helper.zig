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

pub fn getFn(comptime T: type, name: []const u8) std.builtin.Type.Fn {
    if (@hasDecl(T, name)) {
        switch (@typeInfo(@TypeOf(@field(T, name)))) {
            .@"fn" => |@"fn"| return @"fn",
            else => {},
        }
    }

    @compileError("Unexpected type, was given " ++ @typeName(T) ++ " and it didn't have a fn " ++ name ++ " as expected");
}

pub const DeinitType = enum {
    invalid,
    nonAllocator,
    allocator,

    pub fn new(comptime T: type) DeinitType {
        if (@hasDecl(T, "deinit")) {
            switch (@typeInfo(@TypeOf(T.deinit))) {
                .@"fn" => |@"fn"| {
                    if (@"fn".params.len == 1) {
                        const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                        switch (@typeInfo(paramType)) {
                            .pointer => |pointer| {
                                if (pointer.child == T) {
                                    return .nonAllocator;
                                }

                                return .invalid;
                            },
                            else => return .invalid,
                        }
                    }

                    if (@"fn".params.len == 2) {
                        const paramType1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                        const paramType2 = if (@"fn".params[1].type) |@"type"| @"type" else return;

                        switch (@typeInfo(paramType1)) {
                            .pointer => |pointer| {
                                if (pointer.child == T and paramType2 == std.mem.Allocator) {
                                    return .allocator;
                                }

                                return .invalid;
                            },
                            else => return .invalid,
                        }
                    }

                    return .invalid;
                },
                else => return .invalid,
            }
        }

        return .invalid;
    }
};
