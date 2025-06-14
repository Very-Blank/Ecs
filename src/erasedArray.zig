const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const ComponentType = @import("componentManager.zig").ComponentType;
const IndexType = @import("archetype.zig").Row;

pub const ErasedArray = struct {
    handle: *anyopaque,
    swapRemove: *const fn (self: *ErasedArray, i: IndexType) void,
    deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    id: ComponentType,

    pub fn init(comptime T: type, id: ComponentType, allocator: Allocator) ErasedArray {
        const newPtr = allocator.create(std.ArrayListUnmanaged(T)) catch unreachable;
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

    pub fn initWithElement(comptime T: type, component: T, id: ComponentType, allocator: Allocator) ErasedArray {
        const newPtr = allocator.create(std.ArrayListUnmanaged(T)) catch unreachable;
        errdefer allocator.destroy(newPtr);
        newPtr.* = std.ArrayListUnmanaged.empty;
        newPtr.append(allocator, component) catch unreachable;

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
        swapRemove: *const fn (self: *ErasedArray, i: IndexType) void,
        deinit: *const fn (self: *ErasedArray, allocator: Allocator) void,
    } {
        return struct {
            pub fn swapRemove(self: *ErasedArray, i: IndexType) void {
                _ = self.cast(T).swapRemove(i.value());
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
