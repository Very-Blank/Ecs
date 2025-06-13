const std = @import("std");

const Entity = @import("entity.zig");
const ComponentManager = @import("componentManager.zig").ComponentManager;
const Bitset = @import("componentManager.zig").Bitset;
const ULandType = @import("uLandType.zig").ULandType;
const PanicAllocator = @import("panicAllocator.zig").PanicAllocator;

pub const Ecs = struct {
    componentManager: ComponentManager,
    allocator: std.mem.Allocator,
    pub fn createEntity(self: *Ecs, comptime T: type, componets: T) Entity {
        switch (@typeInfo(T)) {
            .@"struct" => |@"struct"| {
                if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
                const bitset = self.componentManager.getBitsetForTuple(T, self.allocator);

                inline for (@"struct".fields) |field| {
                    if (self.hashMap.get(ULandType.getHash(field.type))) |id| {
                        bitset.set(id.value());
                    } else {
                        bitset.set(self.componentManager.registerComponent(self.allocator, field.type).value());
                    }
                }

                inline for (componets, 0..) |component, i| {
                    if (!self.componentManager.hashMap.contains(ULandType.getHash(@"struct".fields[i].type))) {
                        _ = self.componentManager.registerComponent(self.allocator, @"struct".fields[i].type);
                    }
                }
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }

    pub fn destroyEntity(entity: Entity) !void {}
};

