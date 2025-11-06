# Comptime ECS
This is a work in progress ECS that is constructed in comptime removing the need for example type erasure when storing components etc.
It also allows us to assert much more about the ECS since we know that there is only a finite amount of archetypes;
for example we can throw a compile error if the iterator cannot ever match with any archetypes.

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

    var tupleIterator: TupleIterator(&.{ Position, Collider }) = ecs.getTupleIterator(.{.include = .{ .components = &.{ Position, Collider } }}).?;
    defer tupleIterator.deinit();

    while (tupleIterator.next()) |components| {
        std.debug.assert(components[0].x == 4);
        std.debug.assert(components[0].y == 4);

        std.debug.assert(components[1].x == 1);
        std.debug.assert(components[1].y == 0);
    }

    var iterator: Iterator(Position) = ecs.getIterator(.{.component = Position}).?;
    defer iterator.deinit();

    while (iterator.next()) |position| {
        std.debug.assert(position.x == 4);
        std.debug.assert(position.y == 4);
    }
}
```
