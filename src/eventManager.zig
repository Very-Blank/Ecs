const std = @import("std");

const Event = @import("event.zig").Event;
const ULandType = @import("uLandType.zig").ULandType;

pub const EventManager = struct {
    events: []Event,
    keys: []u64,

    pub fn init(comptime T: type, allocator: std.mem.Allocator) EventManager {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (!info.is_tuple or info.fields == 0) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or it was a tuple, but was empty");
                var events: [info.fields.len]Event = undefined;
                var keys: [info.fields.len]u64 = undefined;

                inline for (info.fields, 0..) |field, i| {
                    events[i] = Event.init(field.type, allocator);
                    keys[i] = ULandType.getHash(field.type);
                }
            },
            else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
        }
    }
};
