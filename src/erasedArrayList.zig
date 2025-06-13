const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Component = @import("componentManager.zig").Component;
const Row = @import("entity.zig").RowType;

pub const ErasedArray = struct {
    handle: *anyopaque,
    pop: *const fn (self: *ErasedArray, i: Row, allocator: Allocator) Allocator.Error!ErasedArray,
    transfer: *const fn (self: *ErasedArray, other: *ErasedArray, allocator: Allocator) Allocator.Error!void,
    // orderedRemove: *const fn (self: *ErasedArrayList, i: Row) void,
    swapRemove: *const fn (self: *ErasedArray, i: Row) void,
    deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    id: Component,

    pub fn init(comptime T: type, id: Component, allocator: Allocator) !ErasedArray {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        errdefer allocator.destroy(newPtr);
        newPtr.* = std.ArrayListUnmanaged.empty;

        const functionPtrs = ErasedArray.getFunctionPtrs(T);

        return ErasedArray{
            .handle = newPtr,
            .pop = functionPtrs.pop,
            .transfer = functionPtrs.transfer,
            .deinit = functionPtrs.deinit,
            .id = id,
        };
    }

    pub fn initWithElement(comptime T: type, component: T, id: Component, allocator: Allocator) !ErasedArray {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        errdefer allocator.destroy(newPtr);
        newPtr.* = std.ArrayListUnmanaged.empty;
        try newPtr.append(allocator, component);

        const functionPtrs = ErasedArray.getFunctionPtrs(T);

        return ErasedArray{
            .handle = newPtr,
            .pop = functionPtrs.pop,
            .transfer = functionPtrs.transfer,
            .deinit = functionPtrs.deinit,
            .id = id,
        };
    }

    pub fn getFunctionPtrs(comptime T: type) struct {
        pop: *const fn (self: *ErasedArray, i: Row, allocator: Allocator) ErasedArray,
        transfer: *const fn (self: *ErasedArray, allocator: Allocator) ErasedArray,
        deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    } {
        return struct {
            pub fn pop(self: *ErasedArray, i: Row, allocator: Allocator) Allocator.Error!ErasedArray {
                return try ErasedArray.initWithElement(
                    T,
                    self.cast(T).orderedRemove(i.value()),
                    self.id,
                    allocator,
                );
            }

            // pub fn orderedRemove(self: *ErasedArrayList, i: Row) void {
            //     _ = self.cast(T).orderedRemove(i.value());
            // }

            pub fn swapRemove(self: *ErasedArray, i: Row) void {
                _ = self.cast(T).swapRemove(i.value());
            }

            pub fn transfer(self: *ErasedArray, other: *ErasedArray, i: Row, allocator: Allocator) Allocator.Error!void {
                try other.cast(T).append(
                    allocator,
                    self.cast(T).orderedRemove(i.value()),
                );
            }

            pub fn deinit(self: *ErasedArray, allocator: Allocator) void {
                var ptr = self.cast(T);
                ptr.deinit(allocator);
                allocator.destroy(ptr);
            }
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
