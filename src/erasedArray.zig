const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const ComponentType = @import("componentManager.zig").ComponentType;
const Row = @import("archetype.zig").Row;

pub const ErasedArray = struct {
    handle: *anyopaque,
    swapRemove: *const fn (self: *ErasedArray, i: Row, _allocator: std.mem.Allocator) void,
    deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    id: ComponentType,

    pub fn init(comptime T: type, id: ComponentType, allocator: Allocator) !ErasedArray {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        newPtr.* = std.ArrayListUnmanaged(T).empty;

        return ErasedArray{
            .handle = newPtr,
            .swapRemove = (struct {
                pub fn swapRemove(self: *ErasedArray, i: Row, _allocator: std.mem.Allocator) void {
                    var removed = self.cast(T).swapRemove(i.value());
                    if (@hasDecl(T, "deinit")) {
                        switch (@typeInfo(@TypeOf(T.deinit))) {
                            .@"fn" => |@"fn"| {
                                if (@"fn".params.len == 1) {
                                    const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                    switch (@typeInfo(paramType)) {
                                        .pointer => |pointer| {
                                            if (pointer.child == T) {
                                                T.deinit(&removed);
                                            }
                                        },
                                        else => return,
                                    }
                                } else if (@"fn".params.len == 2) {
                                    const paramType1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                    const paramType2 = if (@"fn".params[1].type) |@"type"| @"type" else return;
                                    switch (@typeInfo(paramType1)) {
                                        .pointer => |pointer| {
                                            if (pointer.child == T and paramType2 == std.mem.Allocator) {
                                                T.deinit(&removed, _allocator);
                                            }
                                        },
                                        else => return,
                                    }
                                }
                            },
                            else => return,
                        }
                    }
                }
            }).swapRemove,
            .deinit = (struct {
                pub fn deinit(self: *ErasedArray, _allocator: Allocator) void {
                    var ptr = self.cast(T);

                    if (@hasDecl(T, "deinit")) {
                        switch (@typeInfo(@TypeOf(T.deinit))) {
                            .@"fn" => |@"fn"| {
                                if (@"fn".params.len == 1) {
                                    const paramType = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                    switch (@typeInfo(paramType)) {
                                        .pointer => |pointer| {
                                            if (pointer.child == T) {
                                                for (ptr.items) |*item| T.deinit(item);
                                            }
                                        },
                                        else => return,
                                    }
                                } else if (@"fn".params.len == 2) {
                                    const paramType1 = if (@"fn".params[0].type) |@"type"| @"type" else return;
                                    const paramType2 = if (@"fn".params[1].type) |@"type"| @"type" else return;
                                    switch (@typeInfo(paramType1)) {
                                        .pointer => |pointer| {
                                            if (pointer.child == T and paramType2 == std.mem.Allocator) {
                                                for (ptr.items) |*item| T.deinit(item, _allocator);
                                            }
                                        },
                                        else => return,
                                    }
                                }
                            },
                            else => return,
                        }
                    }

                    ptr.deinit(_allocator);
                    _allocator.destroy(ptr);
                }
            }).deinit,
            .id = id,
        };
    }

    pub fn append(self: *ErasedArray, comptime T: type, component: T, allocator: Allocator) !void {
        try self.cast(T).append(allocator, component);
    }

    pub fn cast(self: *ErasedArray, comptime T: type) *std.ArrayListUnmanaged(T) {
        return @as(*std.ArrayListUnmanaged(T), @ptrCast(@alignCast(self.handle)));
    }
};

// const ErasedArrayList = struct {};
