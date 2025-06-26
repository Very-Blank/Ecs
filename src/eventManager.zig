const std = @import("std");

const Event = @import("event.zig").Event;
const ULandType = @import("uLandType.zig").ULandType;

pub fn EventManager(
    comptime T: type,
) type {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (!info.is_tuple or info.fields.len == 0) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or it was a tuple, but was empty");
            return struct {
                events: [info.fields.len]Event,
                keys: [info.fields.len]u64,

                const Self = @This();

                pub fn init(allocator: std.mem.Allocator) !Self {
                    var value = Self{ .events = undefined, .keys = undefined };

                    inline for (info.fields, 0..) |field, i| {
                        value.events[i] = try Event.init(field.type, allocator);
                        value.keys[i] = ULandType.getHash(field.type);
                    }

                    return value;
                }

                pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
                    for (&self.events) |*event| {
                        event.deinit(event, allocator);
                    }
                }
            };
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}
