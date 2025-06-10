const std = @import("std");
const Bitset = @import("componentManager.zig").Bitset;
const Entity = @import("entity.zig");

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();

const List = std.ArrayListUnmanaged;
const HashMap = std.AutoArrayHashMapUnmanaged;

pub const Archetype = struct {
    bitset: Bitset,
    components: HashMap(u32, ErasedArrayList),

    pub fn init(components: HashMap(ErasedArrayList), bitset: Bitset) !Archetype {
        return Archetype{
            .bitset = bitset,
            .components = components,
        };
    }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
