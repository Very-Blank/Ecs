# Comptime ECS
This is a work in progress ECS that is constructed at compile time removing the need for example type erasure when storing components.
Comptime also allows us to assert much more about the ECS since we know that there is only a finite amount of archetypes,
we can throw a compile error if the iterator cannot ever match with any archetypes and stack allocate all iterators.

# Examples
```zig
const Collider = struct {
    x: u32,
    y: u32,
};

const Position = struct {
    x: u32,
    y: u32,
};

// Tags are zst that you can add to split existing archetypes.
// For example archtype that has the Template{ .components = &.{Position} } is not the same as an archetype that has Template{ .components = &.{Position}, .tags = &.{Tag} }
const Tag = struct {};

pub fn main() !void {
    var ecs: Ecs(&.{
        .{ .components = &.{ Position, Collider }, .tags = &.{Tag} },
        .{ .components = &.{Position} },
        .{ .components = &.{Position}, .tags = &.{Tag} },
    }) = .init(std.heap.smp_allocator);

    defer ecs.deinit();

    const entity_ptr = ecs.createEntity(
        .{Position{ .x = 4, .y = 4 }},
        &.{},
    );

    try ecs.addTagToEntity(entity_ptr, Tag);
    if (ecs.entityHasTag(entity_ptr, Tag)) {
        std.debug.print("Works!\n", .{});
    }

    try ecs.addComponentToEntity(entity_ptr, Collider{ .x = 1, .y = 0 });
    if (ecs.entityHasComponent(entity_ptr, Collider)) {
        std.debug.print("Works!\n", .{});
    }

    var tupleIterator = ecs.getTupleIterator(.{.include = .{ .components = &.{ Position, Collider } }}).?;

    while (tupleIterator.next()) |components| {
        std.debug.assert(components[0].x == 4);
        std.debug.assert(components[0].y == 4);

        std.debug.assert(components[1].x == 1);
        std.debug.assert(components[1].y == 0);
    }

    var iterator = ecs.getIterator(.{.component = Position}).?;

    while (iterator.next()) |position| {
        std.debug.assert(position.x == 4);
        std.debug.assert(position.y == 4);
    }
}
```
