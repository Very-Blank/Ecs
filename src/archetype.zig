const std = @import("std");
const ComponentList = @import("componentList.zig").ComponentList;
const typeId = @import("typeId.zig");

pub const Archetype = struct {
    entities: std.ArrayList(u32),
    cBuffers: std.ArrayList(ComponentList), // Type-erased component buffers
    allocator: std.mem.Allocator,

    // Component metadata storage
    const ComponentInfo = struct {
        size: usize, // Size of component type in bytes
        alignment: usize, // Alignment requirement
        id: typeId.TypeId, // Unique type identifier
    };

    pub fn init(allocator: std.mem.Allocator) Archetype {
        return .{
            .entities = std.ArrayList(u32).init(allocator),
            .cBuffers = std.ArrayList(ComponentList).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();
        for (self.cBuffers.items) |*array| array.deinit();
        self.cBuffers.deinit();
    }

    // Add new component storage to archetype
    pub fn registerComponent(self: *Archetype, comptime T: type) !void {
        try self.cBuffers.append(try ComponentList.init(T, self.allocator));
    }

    // Get component buffer by type
    pub fn getComponentBuffer(self: *Archetype, comptime T: type) !*ComponentList {
        const target = typeId.get(T);
        for (0..self.cBuffers.items.len) |i| {
            if (self.cBuffers.items[i].typeId == target) {
                return &self.cBuffers.items[i];
            }
        }

        return error.ComponentNotRegistered;
    }
};

//A Small trick
// fn typeId(comptime T: type) u64 {
//     _ = T;
//     const H = struct {
//         var byte: u8 = 0;
//     };
//
//     return @intFromPtr(&H.byte);
// }

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
