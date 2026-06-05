const std = @import("std");
const ecs = @import("ecs.zig");

const EntityPointer = ecs.EntityPointer;
const EntityType = ecs.EntityType;
const GenerationType = ecs.GenerationType;

pub const IndexMode = enum {
    none,
    source,
    destination,
    both,
};

pub fn LinkTable(comptime component_count: usize, comptime tag_count: usize, comptime T: type, mode: IndexMode) type {
    return struct {
        data: if (T != void) [*]T else void = if (T != void) undefined else {},
        sources: [*]EntityPointer = undefined,
        destinations: [*]EntityPointer = undefined,
        capacity: usize = 0,
        len: usize = 0,

        component_bitset: std.bit_set.StaticBitSet(component_count),
        tag_bitset: std.bit_set.StaticBitSet(tag_count),

        source_to_map: if (mode == .source or mode == .both)
            std.AutoHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(usize))
        else
            void = if (mode == .source or mode == .both) .empty else {},

        destination_to_map: if (mode == .destination or mode == .both)
            std.AutoHashMapUnmanaged(EntityType, std.ArrayListUnmanaged(usize))
        else
            void = if (mode == .destination or mode == .both) .empty else {},

        pub const InnerType = T;

        const Self = @This();
        const init_capacity = 4;

        inline fn growCapacity(self: *Self) usize {
            var new = self.capacity;

            while (true) {
                new +|= new / 2 + init_capacity;
                if (self.capacity + 1 <= new)
                    return new;
            }
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (0 < self.capacity) {
                allocator.free(self.data[0..self.capacity]);
                allocator.free(self.sources[0..self.capacity]);
                allocator.free(self.destinations[0..self.capacity]);
            }

            if (mode == .source or mode == .both) {
                var it = self.source_to_map.iterator();
                while (it.next()) |entry| entry.value_ptr.deinit(allocator);
                self.source_to_map.deinit(allocator);
            }

            if (mode == .destination or mode == .both) {
                var it = self.destination_to_map.iterator();
                while (it.next()) |entry| entry.value_ptr.deinit(allocator);
                self.destination_to_map.deinit(allocator);
            }

            self.data = undefined;
            self.sources = undefined;
            self.destinations = undefined;
            self.capacity = 0;
            self.len = 0;

            self.source_to_map = .empty;
            self.destination_to_map = .empty;
        }

        pub fn create(
            self: *Self,
            allocator: std.mem.Allocator,
            source: EntityPointer,
            destination: EntityPointer,
            data: T,
        ) !void {
            std.debug.assert(self.linkIndex(source, destination) == null);
            std.debug.assert(!source.eql(destination));

            if (self.len == self.capacity) {
                const new_capacity = self.growCapacity();

                const new_data = if (T != void) try allocator.alloc(T, new_capacity) else {};
                errdefer if (T != void) allocator.free(new_data);

                const new_sources = try allocator.alloc(EntityPointer, new_capacity);
                errdefer allocator.free(new_sources);

                const new_destinations = try allocator.alloc(EntityPointer, new_capacity);
                errdefer allocator.free(new_destinations);

                if (0 < self.capacity) {
                    if (T != void)
                        @memcpy(new_data[0..self.capacity], self.data[0..self.capacity]);
                    @memcpy(new_sources[0..self.capacity], self.sources[0..self.capacity]);
                    @memcpy(new_destinations[0..self.capacity], self.destinations[0..self.capacity]);

                    allocator.free(self.data[0..self.capacity]);
                    allocator.free(self.sources[0..self.capacity]);
                    allocator.free(self.destinations[0..self.capacity]);
                }

                if (T != void)
                    self.data = new_data.ptr;

                self.sources = new_sources.ptr;
                self.destinations = new_destinations.ptr;
                self.capacity = new_capacity;
            }

            const index = self.len;

            if (T != void)
                self.data[index] = data;

            self.sources[index] = source;
            self.destinations[index] = destination;
            self.len += 1;

            if (mode == .source or mode == .both) {
                const result = try self.source_to_map.getOrPut(allocator, source.entity);
                if (!result.found_existing) result.value_ptr.* = .empty;
                try result.value_ptr.append(allocator, index);
            }

            if (mode == .destination or mode == .both) {
                const result = try self.destination_to_map.getOrPut(allocator, destination.entity);
                if (!result.found_existing) result.value_ptr.* = .empty;
                try result.value_ptr.append(allocator, index);
            }
        }

        pub fn destroy(self: *Self, allocator: std.mem.Allocator, index: usize) void {
            std.debug.assert(index < self.len);

            const last = self.len - 1;

            if (mode == .source or mode == .both) {
                removeFromMap(&self.source_to_map, allocator, self.sources[index].entity, index);
                if (index != last)
                    patchMap(&self.source_to_map, self.sources[last].entity, last, index);
            }

            if (mode == .destination or mode == .both) {
                removeFromMap(&self.destination_to_map, allocator, self.destinations[index].entity, index);
                if (index != last)
                    patchMap(&self.destination_to_map, self.destinations[last].entity, last, index);
            }

            if (index != last) {
                if (T != void)
                    self.data[index] = self.data[last];
                self.sources[index] = self.sources[last];
                self.destinations[index] = self.destinations[last];
            }

            self.len -= 1;
        }

        pub fn destroyAllWithEntity(self: *Self, allocator: std.mem.Allocator, entity: EntityPointer) void {
            if (mode == .none) {
                var i: usize = self.len;
                while (0 < i) : (i -= 1) {
                    const index = i - 1;
                    if (self.sources[index].eql(entity) or self.destinations[index].eql(entity))
                        self.destroy(allocator, index);
                }

                return;
            }

            var indices: std.ArrayListUnmanaged(usize) = .empty;
            defer indices.deinit(allocator);

            if (mode == .source or mode == .both) {
                if ((mode == .source or mode == .both) and self.source_to_map.get(entity)) |list| {
                    for (list.items) |index| {
                        indices.append(allocator, index) catch @panic("OOM");
                    }
                }
            } else {
                for (self.sources[0..self.len], 0..) |source, i| {
                    if (source.eql(entity)) indices.append(allocator, i) catch @panic("OOM");
                }
            }

            if (mode == .destination or mode == .both) {
                if (self.destination_to_map.get(entity)) |list| {
                    for (list.items) |index| {
                        indices.append(allocator, index) catch @panic("OOM");
                    }
                }
            } else {
                for (self.destinations[0..self.len], 0..) |destination, i| {
                    if (destination.eql(entity)) indices.append(allocator, i) catch @panic("OOM");
                }
            }

            std.mem.sort(usize, indices.items, {}, std.sort.desc(usize));

            for (indices.items) |idx| {
                self.destroy(allocator, idx);
            }
        }

        pub fn linkIndex(self: *const Self, src: EntityPointer, dest: EntityPointer) ?usize {
            if (mode == .source or mode == .both) {
                const links = self.linksBySource(src.entity);
                for (links) |link| {
                    if (self.destinations[link].eql(dest)) return link;
                }
            } else if (mode == .destination) {
                const links = self.linksByDestination(dest.entity);
                for (links) |link| {
                    if (self.sources[link].eql(src)) return link;
                }
            } else {
                for (0..self.len) |i| {
                    if (self.sources[i].eql(src) and self.destinations[i].eql(dest)) return i;
                }
            }

            return null;
        }

        pub fn linksBySource(self: *const Self, src: EntityType) []const usize {
            if (mode != .source and mode != .both) @compileError("Unexpected mode: " ++ @tagName(mode) ++ ", expected source or both.");

            return (self.source_to_map.get(src) orelse return &.{}).items;
        }

        pub fn linksByDestination(self: *const Self, dst: EntityType) []const usize {
            if (mode != .destination and mode != .both) @compileError("Unexpected mode: " ++ @tagName(mode) ++ ", expected destination or both.");

            return (self.destination_to_map.get(dst) orelse &.{}).items;
        }

        pub fn getData(self: *const Self) []const T {
            return self.data[0..self.len];
        }

        pub fn getSources(self: *const Self) []const EntityPointer {
            return self.sources[0..self.len];
        }

        pub fn getDestinations(self: *const Self) []const EntityPointer {
            return self.destinations[0..self.len];
        }

        fn removeFromMap(
            map: *std.AutoHashMapUnmanaged(EntityType, std.ArrayList(usize)),
            allocator: std.mem.Allocator,
            entity: EntityType,
            index: usize,
        ) void {
            const list = map.getPtr(entity) orelse return;

            for (list.items, 0..) |v, i| {
                if (v == index) {
                    _ = list.swapRemove(i);
                    break;
                }
            }

            if (list.items.len == 0) {
                list.deinit(allocator);
                std.debug.assert(map.remove(entity));
            }
        }

        fn patchMap(
            map: *std.AutoHashMapUnmanaged(EntityType, std.ArrayList(usize)),
            entity: EntityType,
            old_index: usize,
            new_index: usize,
        ) void {
            const list = map.getPtr(entity) orelse return;
            for (list.items, 0..) |v, i| {
                if (v == old_index) {
                    list.items[i] = new_index;
                    return;
                }
            }
        }
    };
}
