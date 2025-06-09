const std = @import("std");
const ComponentList = @import("componentList.zig").ComponentList;

pub const Archetype = struct {
    entities: std.ArrayList(u32),
    componentList: ComponentList,
    cTypes: std.ArrayList(ComponentInfo), // Store type metadata, not raw types
    cBuffers: std.ArrayList(*anyopaque), // Type-erased component buffers
    allocator: std.mem.Allocator,

    // Component metadata storage
    const ComponentInfo = struct {
        size: usize, // Size of component type in bytes
        alignment: usize, // Alignment requirement
        id: TypeId, // Unique type identifier
    };

    pub fn init(allocator: std.mem.Allocator) Archetype {
        return .{
            .entities = std.ArrayList(u32).init(allocator),
            .cTypes = std.ArrayList(ComponentInfo).init(allocator),
            .cBuffers = std.ArrayList(*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();
        self.cTypes.deinit();
        for (self.cBuffers.items) |array| array.deinit();
        self.cBuffers.deinit();
    }

    // Add new component storage to archetype
    pub fn registerComponent(self: *Archetype, comptime T: type) !void {
        const info = ComponentInfo{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .id = typeId(T),
        };

        // Create and store type-erased buffer
        const buffer = try self.allocator.create(std.ArrayList(T));
        buffer.* = std.ArrayList(T).init(self.allocator);

        try self.cTypes.append(info);
        try self.cBuffers.append(@ptrCast(buffer));
    }

    // Get component buffer by type
    pub fn getComponentBuffer(self: *Archetype, comptime T: type) !*std.ArrayList(T) {
        const target = typeId(T);
        for (self.cTypes.items, 0..) |info, i| {
            if (info.id == target) {
                return @ptrCast(@alignCast(self.cBuffers.items[i]));
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
const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}
