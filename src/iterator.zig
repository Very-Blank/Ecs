const std = @import("std");

pub fn TupleOfArrayLists(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
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

pub fn TupleOfBuffers(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
            var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;
            for (@"struct".fields, 0..) |field, i| {
                new_fields[i] = std.builtin.Type.StructField{
                    .name = &[2:0]u8{ '0' + @as(u8, @intCast(i)), 0 },
                    .type = [][]field.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf([][]field.type),
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

pub fn TupleOfComponents(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
            var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;
            for (@"struct".fields, 0..) |field, i| {
                new_fields[i] = std.builtin.Type.StructField{
                    .name = &[2:0]u8{ '0' + @as(u8, @intCast(i)), 0 },
                    .type = *field.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(*field.type),
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

pub fn TupleIterator(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => |@"struct"| {
            if (!@"struct".is_tuple) @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple.");
            return struct {
                tBuffers: TupleOfBuffers(T),
                currentIndex: u32,
                currentBuffer: u32,

                allocator: std.mem.Allocator,

                const Self = @This();

                pub fn init(tBuffers: TupleOfBuffers(T), allocator: std.mem.Allocator) Self {
                    std.debug.assert(tBuffers.len > 0);
                    inline for (0..@"struct".fields.len) |i| {
                        std.debug.assert(tBuffers[i].len > 0);
                        std.debug.assert(tBuffers[i][0].len > 0);
                    }

                    return .{
                        .tBuffers = tBuffers,
                        .currentIndex = 0,
                        .currentBuffer = 0,
                        .allocator = allocator,
                    };
                }

                // Frees the array that holds the buffers, doesn't touch the actual buffers.
                pub fn deinit(self: *Self) void {
                    inline for (0..@"struct".fields.len) |i| {
                        self.allocator.free(self.tBuffers[i]);
                    }

                    self.tBuffers = undefined;
                }

                pub fn reset(self: *Self) void {
                    self.currentBuffer = 0;
                    self.currentIndex = 0;
                }

                /// Returns the next value in the buffers and whether or not there is next value.
                /// If there is no next value next() will return the last element in the buffers.
                pub fn next(self: *Self) ?TupleOfComponents(T) {
                    if (self.tBuffers[0].len <= self.currentBuffer) {
                        return null;
                    }

                    var value: TupleOfComponents(T) = undefined;
                    inline for (0..@"struct".fields.len) |i| {
                        value[i] = &self.tBuffers[i][self.currentBuffer][self.currentIndex];
                    }

                    if (self.currentIndex + 1 < self.tBuffers[0][self.currentBuffer].len) {
                        self.currentIndex += 1;

                        return value;
                    }

                    self.currentBuffer += 1;
                    self.currentIndex = 0;

                    return value;
                }

                pub fn isNext(self: *Self) bool {
                    return self.currentBuffer < self.tBuffers[0].len;
                }
            };
        },
        else => @compileError("Unexpected type, was given " ++ @typeName(T) ++ ". Expected tuple or a [][]T type."),
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
            std.debug.assert(buffers.len > 0);
            std.debug.assert(buffers[0].len > 0);

            return .{
                .buffers = buffers,
                .currentIndex = 0,
                .currentBuffer = 0,
                .allocator = allocator,
            };
        }

        // Frees the array that holds the buffers, doesn't touch the actual buffers.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffers);
            self.buffers = undefined;
        }

        pub fn reset(self: *Self) void {
            self.currentBuffer = 0;
            self.currentIndex = 0;
        }

        /// Returns the next value in the buffers and whether or not there is next value.
        /// If there is no next value next() will return the last element in the buffers.
        pub fn next(self: *Self) ?*T {
            if (self.buffers.len <= self.currentBuffer) {
                return null;
            }

            const value: *T = &self.buffers[self.currentBuffer][self.currentIndex];

            if (self.currentIndex + 1 < self.buffers[self.currentBuffer].len) {
                self.currentIndex += 1;

                return value;
            }

            self.currentBuffer += 1;
            self.currentIndex = 0;

            return value;
        }

        pub fn isNext(self: *Self) bool {
            return self.currentBuffer < self.buffers.len;
        }
    };
}
