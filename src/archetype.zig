const std = @import("std");
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;
const Entity = @import("entity.zig");

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();
const HashMap = std.AutoArrayHashMapUnmanaged;

pub const Archetype = struct {
    bitset: Bitset,
    sparse: std.ArrayListUnmanaged(Component),
    dense: std.ArrayListUnmanaged(ErasedArrayList),

    pub fn init(bitset: Bitset, allocator: std.mem.Allocator) !Archetype {
        return Archetype{
            .bitset = bitset,
            .sparse = 
            .components = components,
        };
    }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
