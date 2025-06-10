const std = @import("std");
const Component = @import("component.zig").Component;
const ULandType = @import("uLandType.zig").ULandType;

const MAX_COMPONENTS = 32;
pub const Bitset = std.bit_set.StaticBitSet(MAX_COMPONENTS);

const List = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const ComponentManager = struct {
    components: List(u64),
    hashMap: HashMap(u64, u32),

    pub fn init(allocator: Allocator) !ComponentManager {
        return .{
            .components = try List(u64).initCapacity(allocator, 4),
            .hashMap = .empty,
        };
    }

    pub fn deinit(self: *ComponentManager, allocator: Allocator) void {
        self.components.deinit(allocator);
        self.hashMap.deinit(allocator);
    }

    pub fn registerComponent(self: *ComponentManager, allocator: Allocator, comptime T: type) !void {
        if (MAX_COMPONENTS < self.components.items.len + 1) return error.MaxComponentsReached;
        const hash = ULandType.getHash(T);
        try self.components.append(hash);
        try self.hashMap.put(allocator, hash, self.components.items.len - 1);
    }

    pub fn getBitset(self: *ComponentManager, typeIds: []u64) !Bitset {
        std.debug.assert(typeIds.len < MAX_COMPONENTS);
        const bitset = Bitset.initEmpty();
        for (typeIds) |cTypeId| {
            bitset.set(if (self.hashMap.get(cTypeId)) |index| index else return error.ComponentNotRegistered);
        }

        return bitset;
    }
};
