const std = @import("std");
const EntityType = @import("entity.zig").EntityType;

pub const Event = struct {
    handle: *anyopaque,
    clear: *const fn (self: *Event, allocator: std.mem.Allocator) void,
    deinit: *const fn (self: *Event, allocator: std.mem.Allocator) void,

    pub fn init(comptime T: type, allocator: std.mem.Allocator) !Event {
        const newPtr = try allocator.create(std.AutoArrayHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(T)));
        newPtr.* = std.AutoArrayHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(T)).empty;

        return Event{
            .handle = newPtr,
            .clear = (struct {
                pub fn clear(self: *Event, _allocator: std.mem.Allocator) void {
                    var ptr = self.cast(T);
                    const values = ptr.values();
                    for (values) |*value| {
                        value.deinit(_allocator);
                    }
                    ptr.clearAndFree(_allocator);
                }
            }).clear,
            .deinit = (struct {
                pub fn deinit(self: *Event, _allocator: std.mem.Allocator) void {
                    var ptr = self.cast(T);
                    const values = ptr.values();
                    for (values) |*value| {
                        value.deinit(_allocator);
                    }

                    ptr.deinit(_allocator);
                    _allocator.destroy(ptr);
                }
            }).deinit,
        };
    }

    pub fn cast(self: *Event, comptime T: type) *std.AutoArrayHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(T)) {
        return @as(*std.AutoArrayHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(T)), @ptrCast(@alignCast(self.handle)));
    }
};
