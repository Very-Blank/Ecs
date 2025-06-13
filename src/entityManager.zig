const std = @import("std");
const Archetype = @import("archetype.zig").Archetype;

const Entity = @import("entity.zig").Entity;
const ArchetypeId = @import("entity.zig").ArchetypeId;
const Pointer = @import("entity.zig").Pointer;
const Bitset = @import("componentManager.zig").Bitset;
const Component = @import("componentManager.zig").Component;

const MAX_ENTITIES = 5000;

const Allocator = std.mem.Allocator;

const EntityManager = struct {
    unused: std.ArrayListUnmanaged(Entity),
    archetypes: std.ArrayListUnmanaged(Archetype),
    entities: std.AutoArrayHashMapUnmanaged(u16, Pointer),

    len: u32,
};
