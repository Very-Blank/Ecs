const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Component = @import("componentManager.zig").Component;
const Row = @import("entity.zig").Row;

pub const ErasedArrayList = struct {
    ptr: *anyopaque,
    pop: *const fn (self: *ErasedArrayList, i: Row, allocator: Allocator) ErasedArrayList,
    transfer: *const fn (self: *ErasedArrayList, allocator: Allocator) ErasedArrayList,
    // orderedRemove: *const fn (self: *ErasedArrayList, i: Row) void,
    swapRemove: *const fn (self: *ErasedArrayList, i: Row) void,
    deinit: *const fn (self: *ErasedArrayList, allocator: Allocator) void,
    id: Component,

    pub fn init(comptime T: type, id: Component, allocator: Allocator) !ErasedArrayList {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        errdefer allocator.destroy(newPtr);
        newPtr.* = std.ArrayListUnmanaged.empty;

        const functionPtrs = ErasedArrayList.getFunctionPtrs(T);

        return ErasedArrayList{
            .ptr = newPtr,
            .pop = functionPtrs.pop,
            .transfer = functionPtrs.transfer,
            .deinit = functionPtrs.deinit,
            .id = id,
        };
    }

    pub fn initWithElement(comptime T: type, component: T, id: Component, allocator: Allocator) !ErasedArrayList {
        const newPtr = try allocator.create(std.ArrayListUnmanaged(T));
        errdefer allocator.destroy(newPtr);
        newPtr.* = std.ArrayListUnmanaged.empty;
        try newPtr.append(allocator, component);

        const functionPtrs = ErasedArrayList.getFunctionPtrs(T);

        return ErasedArrayList{
            .ptr = newPtr,
            .pop = functionPtrs.pop,
            .transfer = functionPtrs.transfer,
            .deinit = functionPtrs.deinit,
            .id = id,
        };
    }

    pub fn getFunctionPtrs(comptime T: type) struct {
        pop: *const fn (self: *ErasedArrayList, i: Row, allocator: Allocator) ErasedArrayList,
        transfer: *const fn (self: *ErasedArrayList, allocator: Allocator) ErasedArrayList,
        deinit: *const fn (self: *ErasedArrayList, allocator: Allocator) void,
    } {
        return struct {
            pub fn pop(self: *ErasedArrayList, i: Row, allocator: Allocator) !ErasedArrayList {
                return try ErasedArrayList.initWithElement(
                    T,
                    self.cast(T).orderedRemove(i.value()),
                    self.id,
                    allocator,
                );
            }

            // pub fn orderedRemove(self: *ErasedArrayList, i: Row) void {
            //     _ = self.cast(T).orderedRemove(i.value());
            // }

            pub fn swapRemove(self: *ErasedArrayList, i: Row) void {
                _ = self.cast(T).swapRemove(i.value());
            }

            pub fn transfer(self: *ErasedArrayList, other: *ErasedArrayList, i: Row, allocator: Allocator) !ErasedArrayList {
                try other.cast(T).append(
                    allocator,
                    self.cast(T).orderedRemove(i.value()),
                );
            }

            pub fn deinit(self: *ErasedArrayList, allocator: Allocator) void {
                var ptr = self.cast(T);
                ptr.deinit(allocator);
                allocator.destroy(ptr);
            }
        };
    }

    pub fn append(self: *ErasedArrayList, comptime T: type, component: T, allocator: Allocator) *std.ArrayListUnmanaged(T) {
        self.cast(T).append(allocator, component);
    }

    pub fn cast(self: *ErasedArrayList, comptime T: type) *std.ArrayListUnmanaged(T) {
        return @as(*std.ArrayListUnmanaged(T), @ptrCast(@alignCast(self.ptr)));
    }
};

// const ErasedArrayList = struct {};
