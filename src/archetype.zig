const std = @import("std");
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;
const MAX_COMPONENTS = @import("componentManager.zig").MAX_COMPONENTS;
const Entity = @import("entity.zig").Entity;

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();
const HashMap = std.AutoArrayHashMapUnmanaged;

pub const Archetype = struct {
    bitset: Bitset,
    entities: std.ArrayListUnmanaged(Entity),
    sparse: [MAX_COMPONENTS]u8,
    dense: std.ArrayListUnmanaged(ErasedArrayList),

    // pub fn init(bitset: Bitset, dense: std.ArrayListUnmanaged(ErasedArrayList)) !Archetype {
    //     var sparse: [MAX_COMPONENTS]u8 = undefined;
    //     const count = bitset.count();
    //
    //     return Archetype{
    //         .bitset = bitset,
    //         .sparse = .empty,
    //         .dense = .empty,
    //     };
    // }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }
};
