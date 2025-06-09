const std = @import("std");
const ComponentBuffer = @import("componentBuffer.zig").ComponentBuffer;
const Bitset = @import("componentManager.zig").Bitset;
const Entity = @import("entity.zig");
const typeId = @import("typeId.zig").typeId;

pub const Archetype = struct {
    bitset: Bitset,
    entities: std.ArrayList(Entity),
    components: std.ArrayList(ComponentBuffer),
    hashMap: std.AutoHashMap(u64, u64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Archetype {
        return .{
            .entities = std.ArrayList(u32).init(allocator),
            .cBuffers = std.ArrayList(ComponentBuffer).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();
        for (self.cBuffers.items) |*array| array.deinit();
        self.cBuffers.deinit();
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
