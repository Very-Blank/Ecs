const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const typeId = @import("typeId.zig");

pub fn ErasedArrayList() type {
    switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{
            return struct {
                /// NOTE: DEBUG info on the actual type
                typeId: typeId.TypeId,
                /// Pointer to the actual list
                ptr: *anyopaque,
                deinit: *const fn (self: *Self, _allocator: Allocator) void,
                /// Components ID
                id: u32,
                const Self = @This();
                pub fn init(comptime T: type, id: u32, allocator: Allocator) !Self {
                    std.debug.print("u64: {any}\n", .{@intFromPtr(typeId.get(u64))});
                    const newPtr = try allocator.create(List(T));
                    newPtr.* = try List(T).initCapacity(allocator, 1);
                    return Self{
                        .typeId = typeId.get(T),
                        .id = id,
                        .ptr = newPtr,
                        .deinit = (struct {
                            pub fn deinit(self: *Self, _allocator: Allocator) void {
                                var ptr = self.cast(T);
                                ptr.deinit(_allocator);
                                _allocator.destroy(ptr);
                            }
                        }).deinit,
                    };
                }
                pub fn cast(self: *Self, comptime T: type) *List(T) {
                    std.debug.assert(self.typeId == typeId.get(T));
                    return @as(*List(T), @ptrCast(@alignCast(self.ptr)));
                }
            },
        },
        .ReleaseFast, .ReleaseSmall => .{
            return struct {
                /// Pointer to the actual list
                ptr: *anyopaque,
                deinit: fn (self: *Self, _allocator: Allocator) void,
                /// Components ID
                id: u32,
                const Self = @This();
                pub fn init(comptime T: type, id: u32, allocator: Allocator) Self {
                    const newPtr = try allocator.create(List(T));
                    newPtr.* = List(T).initCapacity(allocator, 1);
                    return Self{
                        .id = id,
                        .ptr = newPtr,
                        .deinit = (struct {
                            pub fn deinit(self: *Self, _allocator: Allocator) void {
                                var ptr = self.cast(T);
                                ptr.deinit(_allocator);
                                _allocator.destroy(ptr);
                            }
                        }).deinit,
                    };
                }
                pub fn cast(self: *Self, comptime T: type) *List(T) {
                    return @as(*List(T), @ptrCast(@alignCast(self.ptr)));
                }
            },
        },
    }
}

// const ErasedArrayList = struct {};
