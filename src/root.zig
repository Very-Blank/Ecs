pub const Ecs = @import("ecs.zig").Ecs;
pub const Template = @import("Template.zig");

pub const EntityPointer = @import("ecs.zig").EntityPointer;
pub const EntityID = @import("ecs.zig").EntityID;
// pub const SingletonType = @import("ecs.zig").SingletonType;

pub const GenericIterator = @import("iterator.zig").GenericIterator;
pub const GenericTupleIterator = @import("tupleIterator.zig").GenericTupleIterator;

test " " {
    _ = @import("ecs.zig");
}
