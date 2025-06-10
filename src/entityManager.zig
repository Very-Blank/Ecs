const std = @import("std");
const List = std.ArrayListUnmanaged;
const entity = @import("entity.zig");

const HashMap = std.AutoHashMapUnmanaged;
const EntityManager = struct {
    /// How many entities are currently
    len: u32,
    /// List of unused entity Id's
    unused: List(entity.UnusedEntity),
    /// Using the generation we check that Entity.generation == Pointer.generation
    entitys: HashMap(u32, entity.Pointer),
};
