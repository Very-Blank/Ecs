const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const ComponentType = @import("componentManager.zig").ComponentType;
const Row = @import("archetype.zig").Row;

pub const ErasedArray = struct {
    handle: *anyopaque,
    swapRemove: *const fn (self: *ErasedArray, i: Row) void,
    deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    id: ComponentType,

    pub fn init(comptime T: type, id: ComponentType, allocator: Allocator) !ErasedArray {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        newPtr.* = std.ArrayListUnmanaged(T).empty;

        return ErasedArray{
            .handle = newPtr,
            .swapRemove = (struct {
                pub fn swapRemove(self: *ErasedArray, i: Row) void {
                    _ = self.cast(T).swapRemove(i.value());
                }
            }).swapRemove,
            .deinit = (struct {
                pub fn deinit(self: *ErasedArray, _allocator: Allocator) void {
                    var ptr = self.cast(T);
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
