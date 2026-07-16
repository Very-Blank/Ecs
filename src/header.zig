const std = @import("std");

pub const Field = struct {
    name: []const u8,
    type: type,
    default_value_ptr: ?*const anyopaque = null,
};

/// Padding is added to the very end.
/// Headers are forced to have no padding in between field members.
pub fn Header(
    comptime fields: []const Field,
    comptime padding: comptime_int,
) type {
    for (0..fields.len) |i| {
        for (i + 1..fields.len) |j| {
            if (std.mem.eql(u8, fields[i].name, fields[j].name))
                @compileError("Field name: " ++ fields[i].name ++ " is used twice, " ++ std.fmt.comptimePrint(
                    "at index {any} and {any}",
                    .{ i, j },
                ) ++ ".");
        }
    }

    if (1 < fields.len) {
        var offset = 0;
        for (fields) |field| {
            if (-offset & (@alignOf(field.type) - 1) != 0)
                @compileError("Field " ++ field.name ++ " needs " ++ std.fmt.comptimePrint(
                    "{any}",
                    .{-offset & (@alignOf(field.type) - 1)},
                ) ++ " bytes of padding before it.");
            offset += @sizeOf(field.type);
        }
    }

    return struct {
        ptr: [*]u8,

        const Self = @This();

        pub inline fn field(self: Self, comptime name: []const u8) init: {
            for (fields) |capture|
                if (std.mem.eql(u8, name, capture.name)) break :init *capture.type;

            @compileError("Field " ++ name ++ ", doesn't exist.");
        } {
            return @ptrCast(
                @alignCast(
                    self.ptr + (comptime init: {
                        var offset: comptime_int = 0;

                        for (fields) |capture| {
                            if (std.mem.eql(u8, name, capture.name)) break :init offset;
                            offset += @sizeOf(capture.type);
                        }

                        @compileError("Field " ++ name ++ ", doesn't exist.");
                    }),
                ),
            );
        }

        pub inline fn fieldByIndex(self: Self, comptime index: comptime_int) init: {
            if (fields.len <= index)
                @compileError("Field index out of range.");

            break :init *fields[index].type;
        } {
            return @ptrCast(
                @alignCast(
                    self.ptr + (comptime init: {
                        var offset: comptime_int = 0;

                        for (fields[0..index]) |capture| {
                            offset += @sizeOf(capture.type);
                        }

                        break :init offset;
                    }),
                ),
            );
        }

        pub fn write(self: Self, values: @Struct(
            .auto,
            null,
            &(names: {
                var names: [fields.len][]const u8 = undefined;

                for (fields, 0..) |capture, i| {
                    names[i] = capture.name;
                }

                break :names names;
            }),
            &(types: {
                var types: [fields.len]type = undefined;

                for (fields, 0..) |capture, i| {
                    types[i] = capture.type;
                }

                break :types types;
            }),
            &(attributes: {
                var attributes: [fields.len]std.builtin.Type.StructField.Attributes = .{std.builtin.Type.StructField.Attributes{}} ** fields.len;

                for (fields, 0..) |capture, i| {
                    attributes[i].default_value_ptr = capture.default_value_ptr;
                }

                break :attributes attributes;
            }),
        )) void {
            inline for (fields, 0..) |capture, i| {
                self.fieldByIndex(i).* = @field(values, capture.name);
            }
        }

        pub inline fn arrayable() bool {
            return -size() & (alignment() - 1) == 0;
        }

        pub inline fn size() comptime_int {
            return comptime init: {
                var sum = padding;

                for (fields) |capture|
                    sum += @sizeOf(capture.type);

                break :init sum;
            };
        }

        pub inline fn alignment() comptime_int {
            return comptime init: {
                var largest = 1;

                for (fields) |capture|
                    if (largest < @alignOf(capture.type)) {
                        largest = @alignOf(capture.type);
                    };

                break :init largest;
            };
        }
    };
}
