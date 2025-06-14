const std = @import("std");
const Archetype = @import("archetype.zig").Archetype;

const EntityType = @import("entity.zig").EntityType;
const ArchetypeType = @import("entity.zig").ArchetypeType;
const SlimPointer = @import("entity.zig").SlimPointer;
const FatPointer = @import("entity.zig").FatPointer;
const GenerationType = @import("entity.zig").GenerationType;
const ArchetypeId = @import("entity.zig").ArchetypeId;
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").ComponentType;

const MAX_ENTITIES = 5000;

const Allocator = std.mem.Allocator;

pub const EntityManager = struct {
    unused: std.ArrayListUnmanaged(SlimPointer),
    archetypes: std.ArrayListUnmanaged(Archetype),
    entityMap: std.AutoArrayHashMapUnmanaged(EntityType, FatPointer),
    archetypeMap: std.AutoArrayHashMapUnmanaged(Bitset, ArchetypeType),
    len: u32,

    pub const init = EntityManager{
        .unused = .empty,
        .archetypes = .empty,
        .entityMap = .empty,
        .archetypeMap = .empty,
        .len = 0,
    };

    pub fn deinit(self: *EntityManager, allocator: std.mem.Allocator) void {
        self.unused.deinit(allocator);
        for (self.archetypes.items) |*archetype| archetype.deinit(allocator);
        self.archetypes.deinit(allocator);
        self.entityMap.deinit(allocator);
        self.archetypeMap.deinit(allocator);
    }

    pub fn getNewEntity(self: *EntityManager) SlimPointer {
        if (self.unused.pop()) |slimPointer| {
            return SlimPointer{ .entity = slimPointer.entity, .generation = GenerationType.make(slimPointer.generation.value() +% 1) };
        }

        self.len += 1;
        return SlimPointer{ .entity = EntityType.make(self.len - 1), .generation = GenerationType.make(0) };
    }
};
