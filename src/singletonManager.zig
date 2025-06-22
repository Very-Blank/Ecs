const std = @import("std");
const SlimPointer = @import("entity.zig").SlimPointer;

const Bitset = @import("componentManager.zig").Bitset;

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
    singletons: std.ArrayListUnmanaged(Bitset),
    singletonToEntityMap: std.AutoHashMapUnmanaged(SingletonType, SlimPointer),

    pub const init = SingletonManager{ .singletons = .empty, .singletonToEntityMap = .empty };

    pub fn deinit(self: *SingletonManager, allocator: std.mem.Allocator) void {
        self.singletons.deinit(allocator);
        self.singletonToEntityMap.deinit(allocator);
    }
};
