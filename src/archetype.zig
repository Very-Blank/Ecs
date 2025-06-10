const std = @import("std");
const ComponentBuffer = @import("componentBuffer.zig").ComponentBuffer;
const Bitset = @import("componentManager.zig").Bitset;
const Entity = @import("entity.zig");

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();

const List = std.ArrayListUnmanaged;

pub const Archetype = struct {
    bitset: Bitset,
    // entities: List(Entity),
    components: std.AutoArrayHashMapUnmanaged(u64, ErasedArrayList),
    // hashMap: std.AutoHashMap(u64, u64),
    // allocator: std.mem.Allocator,

    /// Components, must be sorted
    pub fn init(entity: Entity, components: List(ErasedArrayList), bitset: Bitset, allocator: std.mem.Allocator) !Archetype {
        var archetype = Archetype{
            .bitset = bitset,
            .entities = try std.ArrayListUnmanaged(Entity).initCapacity(allocator, 1),
            .components = components,
            .allocator = allocator,
        };

        errdefer archetype.entities.deinit(allocator);
        archetype.entities.append(entity);

        return archetype;
    }

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        self.entities.deinit(allocator);
        for (self.components.items) |*array| array.deinit(allocator);
        self.components.deinit();
    }

    // // Add new component storage to archetype
    // pub fn registerComponent(self: *Archetype, comptime T: type) !void {
    //     try self.cBuffers.append(try ComponentBuffer.init(T, self.allocator));
    // }
    //
    // // Get component buffer by type
    // pub fn getComponentBuffer(self: *Archetype, comptime T: type) !*ComponentBuffer {
    //     const target = typeId(T);
    //     for (0..self.cBuffers.items.len) |i| {
    //         if (self.cBuffers.items[i].typeId == target) {
    //             return &self.cBuffers.items[i];
    //         }
    //     }
    //
    //     return error.ComponentNotRegistered;
    // }
};

// https://github.com/ziglang/zig/issues/19858#issuecomment-2369861301
// const TypeId = *const struct {
//     _: u8,
// };
//
// pub inline fn typeId(comptime T: type) TypeId {
//     return &struct {
//         comptime {
//             _ = T;
//         }
//         var id: @typeInfo(TypeId).pointer.child = undefined;
//     }.id;
// }
