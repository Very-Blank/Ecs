const std = @import("std");

pub fn TupleOfArrayLists(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;
            for (@"struct".fields, 0..) |field, i| {
                new_fields[i] = std.builtin.Type.StructField{
                    .name = &[2:0]u8{ '0' + @as(u8, @intCast(i)), 0 },
                    .type = std.ArrayListUnmanaged([]field.type),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(std.ArrayListUnmanaged([]field.type)),
                };
            }

            return @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &new_fields,
                    .decls = &.{},
                    .is_tuple = true,
                },
            });
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn TupleOfIterators(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;
            for (@"struct".fields, 0..) |field, i| {
                new_fields[i] = std.builtin.Type.StructField{
                    .name = &[2:0]u8{ '0' + @as(u8, @intCast(i)), 0 },
                    .type = Iterator(field.type),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(Iterator(field.type)),
                };
            }
            return @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &new_fields,
                    .decls = &.{},
                    .is_tuple = true,
                },
            });
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple."),
    }
}

pub fn Iterator(comptime T: type) type {
    return struct {
        buffers: [][]T,
        currentIndex: u32,
        currentBuffer: u32,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(buffers: [][]T, allocator: std.mem.Allocator) Self {
            return .{
                .buffers = buffers,
                .currentIndex = 0,
                .currentBuffer = 0,
                .allocator = allocator,
            };
        }

        // Frees the array that holds the buffers, doesn't touch the actual buffers.
        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.buffers);
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) struct { *T, bool } {
            const value: *T = &self.buffers[self.currentBuffer][self.currentIndex];

            if (self.currentIndex + 1 < self.buffers[self.currentBuffer].len) {
                self.currentIndex += 1;

                return .{ value, true };
            } else if (self.currentBuffer + 1 < self.buffers.len) {
                self.currentBuffer += 1;
                self.currentIndex = 0;

                return .{ value, true };
            }

            return .{ value, false };
        }
    };
}
