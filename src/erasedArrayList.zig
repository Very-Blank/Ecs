const std = @import("std");
const builtin = @import("builtin");
const ULandType = @import("uLandType.zig").ULandType;

const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub fn ErasedArrayList() type {
    switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{
            return struct {
                /// NOTE: DEBUG info on the actual type
                type: ULandType,
                /// Pointer to the actual list
                ptr: *anyopaque,
                pop: *const fn (self: *Self, i: u32, _allocator: Allocator) Self,
                transfer: *const fn (self: *Self, _allocator: Allocator) Self,
                deinit: *const fn (self: *Self, _allocator: Allocator) void,
                /// Components ID
                id: u32,
                const Self = @This();
                pub fn init(comptime T: type, id: u32, allocator: Allocator) !Self {
                    const newPtr = try allocator.create(List(T));
                    newPtr.* = try List(T).initCapacity(allocator, 1);
                    return Self{
                        .type = ULandType.get(T),
                        .id = id,
                        .ptr = newPtr,
                        .pop = (struct {
                            pub fn pop(self: *Self, i: u32, _allocator: Allocator) !Self {
                                var oldList = self.cast(T);
                                const eNewList = try Self.init(T, self.id, _allocator);
                                var newList = eNewList.cast(T);
                                try newList.append(oldList.orderedRemove(i));
                                return newList;
                            }
                        }).popup,
                        .transfer = (struct {
                            pub fn transfer(self: *Self, other: *Self, i: u32, _allocator: Allocator) !Self {
                                std.debug.assert(self.type.eql(other.type.*));
                                var sList = self.cast(T);
                                var oList = other.cast(T);
                                try oList.append(_allocator, sList.orderedRemove(i));
                            }
                        }).transfer,
                        .deinit = (struct {
                            pub fn deinit(self: *Self, _allocator: Allocator) void {
                                var ptr = self.cast(T);
                                ptr.deinit(_allocator);
                                _allocator.destroy(ptr);
                            }
                        }).deinit,
                    };
                }
                pub fn append(self: *Self, comptime T: type, component: T, allocator: Allocator) *List(T) {
                    self.cast(T).append(allocator, component);
                }
                pub fn cast(self: *Self, comptime T: type) *List(T) {
                    std.debug.assert(self.type.eql(ULandType.get(T)));
                    return @as(*List(T), @ptrCast(@alignCast(self.ptr)));
                }
            },
        },
        .ReleaseFast, .ReleaseSmall => .{
            return struct {
                /// Pointer to the actual list
                ptr: *anyopaque,
                pop: *const fn (self: *Self, i: u32, _allocator: Allocator) Self,
                transfer: *const fn (self: *Self, _allocator: Allocator) Self,
                deinit: *const fn (self: *Self, _allocator: Allocator) void,
                /// Components ID
                id: u32,
                const Self = @This();
                pub fn init(comptime T: type, id: u32, allocator: Allocator) Self {
                    const newPtr = try allocator.create(List(T));
                    newPtr.* = List(T).initCapacity(allocator, 1);
                    return Self{
                        .id = id,
                        .ptr = newPtr,
                        .pop = (struct {
                            pub fn pop(self: *Self, i: u32, _allocator: Allocator) !Self {
                                var oldList = self.cast(T);
                                const eNewList = try Self.init(T, self.id, _allocator);
                                var newList = eNewList.cast(T);
                                try newList.append(oldList.orderedRemove(i));
                                return newList;
                            }
                        }).popup,
                        .transfer = (struct {
                            pub fn transfer(self: *Self, other: *Self, i: u32, _allocator: Allocator) !Self {
                                var sList = self.cast(T);
                                var oList = other.cast(T);
                                try oList.append(_allocator, sList.orderedRemove(i));
                            }
                        }).transfer,
                        .deinit = (struct {
                            pub fn deinit(self: *Self, _allocator: Allocator) void {
                                var ptr = self.cast(T);
                                ptr.deinit(_allocator);
                                _allocator.destroy(ptr);
                            }
                        }).deinit,
                    };
                }
                pub fn append(self: *Self, comptime T: type, component: T, allocator: Allocator) *List(T) {
                    self.cast(T).append(allocator, component);
                }
                pub fn cast(self: *Self, comptime T: type) *List(T) {
                    return @as(*List(T), @ptrCast(@alignCast(self.ptr)));
                }
            },
        },
    }
}

// const ErasedArrayList = struct {};
