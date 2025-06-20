const std = @import("std");
const ULandType = @import("uLandType.zig").ULandType;

pub const MAX_COMPONENTS = 32;
pub const Bitset = std.bit_set.StaticBitSet(MAX_COMPONENTS);

const List = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

pub const ComponentType = enum(u32) {
    _,
    pub inline fn make(@"u32": u32) ComponentType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": ComponentType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const ComponentManager = struct {
    components: std.ArrayListUnmanaged(u64),
    hashMap: std.AutoHashMapUnmanaged(u64, ComponentType),

    pub const init = ComponentManager{
        .components = .empty,
        .hashMap = .empty,
    };

    pub fn deinit(self: *ComponentManager, allocator: Allocator) void {
        self.components.deinit(allocator);
        self.hashMap.deinit(allocator);
    }

    pub fn registerComponent(self: *ComponentManager, allocator: Allocator, comptime T: type) ComponentType {
        std.debug.assert(self.components.items.len + 1 <= MAX_COMPONENTS);
        const hash = ULandType.getHash(T);
        self.components.append(allocator, hash) catch unreachable;
        self.hashMap.put(allocator, hash, ComponentType.make(@intCast(self.components.items.len - 1))) catch unreachable;

        return ComponentType.make(@intCast(self.components.items.len - 1));
    }
};
