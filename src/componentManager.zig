const std = @import("std");
const ULandType = @import("uLandType.zig").ULandType;

pub const MAX_COMPONENTS = 32;
pub const Bitset = std.bit_set.StaticBitSet(MAX_COMPONENTS);

const List = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

pub const Component = enum(u8) {
    _,
    pub inline fn make(@"u8": u8) Component {
        return @enumFromInt(@"u8");
    }

    pub inline fn value(@"enum": Component) u8 {
        return @intFromEnum(@"enum");
    }
};

pub const ComponentManager = struct {
    components: std.ArrayListUnmanaged(u64),
    hashMap: std.AutoHashMapUnmanaged(u64, Component),

    pub fn init(allocator: Allocator) !ComponentManager {
        return .{
            .components = try std.ArrayListUnmanaged(u64).initCapacity(allocator, 4),
            .hashMap = .empty,
        };
    }

    pub fn deinit(self: *ComponentManager, allocator: Allocator) void {
        self.components.deinit(allocator);
        self.hashMap.deinit(allocator);
    }

    pub fn registerComponent(self: *ComponentManager, allocator: Allocator, comptime T: type) Component {
        std.debug.assert(MAX_COMPONENTS < self.components.items.len + 1);
        const hash = ULandType.getHash(T);
        self.components.append(allocator, hash) catch unreachable;
        self.hashMap.put(allocator, hash, self.components.items.len - 1) catch unreachable;

        return Component.make(self.components.items.len - 1);
    }

    pub fn getBitsetForTuple(self: *ComponentManager, T: type, allocator: Allocator) Bitset {
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
