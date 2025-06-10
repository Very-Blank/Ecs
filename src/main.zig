const std = @import("std");
const builtin = @import("builtin");
const Archetype = @import("archetype.zig").Archetype;
const typeId = @import("typeId.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const Position = struct {
    x: u32,
    y: u32,
};

const ErasedArrayList = @import("erasedArrayList.zig").ErasedArrayList();

pub fn main() !void {
    const allocator: std.mem.Allocator, const is_debug: bool = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        std.debug.print("Debug allocator: {any}\n", .{debug_allocator.deinit()});
    };

    var erasedPositions = try ErasedArrayList.init(Position, 0, allocator);
    defer erasedPositions.deinit(&erasedPositions, allocator);
    var positions = erasedPositions.cast(Position);
    try positions.append(allocator, .{ .x = 100, .y = 100 });

    std.debug.print("u32: {any}\n", .{@intFromPtr(typeId.get(u32))});
    std.debug.print("f32: {any}\n", .{@intFromPtr(typeId.get(f32))});
    std.debug.print("f32: {any}\n", .{@intFromPtr(typeId.get(f32))});
    std.debug.print("u64: {any}\n", .{@intFromPtr(typeId.get(u64))});
    std.debug.print("positions.items[0] = {any}\n", .{positions.items[0]});

    // var archetype = Archetype.init(allocator);
    // defer archetype.deinit();
    // try archetype.registerComponent(Position);
    //
    // const positions = try archetype.getComponentBuffer(Position);
    // try positions.append(Position, .{ .x = 10, .y = 20 });
    // try positions.append(Position, .{ .x = 38, .y = 3434 });
    // try positions.append(Position, .{ .x = 868, .y = 44 });
    //
    // const position: *Position = positions.get(Position, 0);
    // position.*.x = 500;
    // position.*.y = 40000;
    // positions.remove(0);
    //
    // std.debug.print("{any}\n", .{positions.get(Position, 0)});
    // std.debug.print("{any}\n", .{positions.get(Position, 1)});
}
