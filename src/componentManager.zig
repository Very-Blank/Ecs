const std = @import("std");
const Component = @import("component.zig").Component;
const typeId = @import("typeId.zig").typeId;

const MAX_COMPONENTS = 32;
pub const Bitset = std.bit_set.StaticBitSet(MAX_COMPONENTS);

const ComponentManager = struct {
    components: std.ArrayList(Component),
    hashMap: std.AutoHashMap(u64, u64),

    pub fn init(allocator: std.mem.Allocator) !ComponentManager {
        return .{
            .components = try std.ArrayList(Component).init(allocator),
            .hashMap = try std.AutoHashMap(u64, u64).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentManager) void {
        self.components.deinit();
        self.hashMap.deinit();
    }

    pub fn registerComponent(self: *ComponentManager, comptime T: type) !void {
        if (MAX_COMPONENTS < self.components.items.len + 1) return error.MaxComponentsReached;
        try self.components.append(Component.new(T));
    }

    pub fn getComponentById(self: *ComponentManager, i: u64) Component {
        // NOTE: Asserts rather than returns error because a faulty error is really bad BUG!
        std.debug.assert(i < self.components.items.len);
        return self.components.items[i];
    }

    pub fn getComponentByType(self: *ComponentManager, comptime T: type) Component {
        const cTypeId = typeId(T);
        return if (self.hashMap.get(cTypeId)) |index| return self.components.items[index] else return error.ComponentNotRegistered;
    }

    pub fn getComponentByTypeId(self: *ComponentManager, cTypeId: u64) !Component {
        return if (self.hashMap.get(cTypeId)) |index| return self.components.items[index] else return error.ComponentNotRegistered;
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
