# Comptime ECS

A work in progress ECS that is constructed at compile time.

## Why comptime?

Building it at compile time means:

- Queries are resolved at compile time (no runtime archetype matching).
- Iterators are guaranteed to be stack allocated, even though we use archetypes.
- No book keeping of components at runtime.

# Memory layout

The ECS is laid out as a single contiguous allocation (? Means it's compile time
known length):

1. `EcsHeader`
2. `[?] ArchetypeHeader`
3. `[?][?]Offsets (u32)`
4. `[]struct { Archetype (u32), Row (u32), Generation (u32), State (u32)}`
5. `[]Entities (u32)`, Used by archetypes as back reference, but also for
   iterators to get current iterated entity.
6. `[?][]Component`

```
Entity -> (Archetype, Row, Generation, State)
```

We also take great deal of care not to use pointers and rather use offsets `u32`
inside the ECS to make it fully serializable.

Padding is only added to keep components aligned.

# Usage

```zig
// TODO:
```
