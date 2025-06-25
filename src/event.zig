const std = @import("std");

pub const Event = struct {
    handle: *anyopaque,
    clear: *const fn (self: *Event, allocator: std.mem.Allocator) void,
    deinit: *const fn (self: *Event, allocator: std.mem.Allocator) void,

    pub fn init(comptime T: type, allocator: std.mem.Allocator) Event {
        const newPtr = try allocator.create(std.HashMapUnmanaged(T));
        newPtr.* = std.HashMapUnmanaged(T).empty;
        return Event{
            .handle = undefined,
            .clear = (struct {
                pub fn clear(self: *Event, _allocator: std.mem.Allocator) void {
                    var ptr = self.cast(T);
                    ptr.clearAndFree(_allocator);
                }
            }).clear,
            .deinit = (struct {
                pub fn deinit(self: *Event, _allocator: std.mem.Allocator) void {
                    var ptr = self.cast(T);
                    ptr.deinit(_allocator);
                    _allocator.destroy(ptr);
                }
            }).deinit,
        };
    }

    pub fn cast(self: *Event, comptime T: type) *std.HashMapUnmanaged(T) {
        return @as(*std.HashMapUnmanaged(T), @ptrCast(@alignCast(self.handle)));
    }
};
