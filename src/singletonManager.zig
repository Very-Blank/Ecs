const std = @import("std");
const SlimPointer = @import("entity.zig").SlimPointer;

pub const SingletonType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) SingletonType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": SingletonType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const SingletonManager = struct {
    singletonToEntityMap: std.AutoHashMapUnmanaged(SingletonType, SlimPointer),
    len: u32,

    pub const init = SingletonManager{ .singletonToEntityMap = .empty, .len = 0 };

    pub fn deinit(self: *SingletonManager, allocator: std.mem.Allocator) void {
        self.singletonToEntityMap.deinit(allocator);
    }
};
