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
        std.debug.assert(MAX_COMPONENTS < self.components.items.len + 1);
        const hash = ULandType.getHash(T);
        self.components.append(allocator, hash) catch unreachable;
        self.hashMap.put(allocator, hash, self.components.items.len - 1) catch unreachable;

        return ComponentType.make(self.components.items.len - 1);
    }

    pub fn getBitsetForTuple(self: *ComponentManager, comptime T: type, allocator: Allocator) Bitset {
        var bitset = Bitset.initEmpty();
        switch (@typeInfo(T)) {
            .@"struct" => |@"struct"| {
                if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
                inline for (@"struct".fields) |field| {
                    if (self.hashMap.get(ULandType.getHash(field.type))) |id| {
                        bitset.set(id.value());
                    } else {
                        bitset.set(self.registerComponent(allocator, field.type).value());
                    }
                }
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }

    // pub fn getBitset(self: *ComponentManager, T: []u64) !Bitset {
    //     std.debug.assert(MAX_COMPONENTS < self.components.items.len + 1);
    //     const bitset = Bitset.initEmpty();
    //     for (typeIds) |cTypeId| {
    //         bitset.set(if (self.hashMap.get(cTypeId)) |index| index else return error.ComponentNotRegistered);
    //     }
    //
    //     return bitset;
    // }
};
