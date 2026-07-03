const std = @import("std");

pub const Field = struct {
    name: []const u8,
    type: type,
};

/// Padding is added to the very end.
/// Headers are forced to have no padding in between field members.
pub fn Header(
    fields: []const Field,
    padding: comptime_int,
) type {
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

        pub inline fn arrayable() bool {
            return -size() & (alignment() - 1) == 0;
        }

        pub inline fn size() comptime_int {
            var sum = padding;

            for (fields) |capture|
                sum += @sizeOf(capture.type);

            return sum;
        }

        pub inline fn alignment() comptime_int {
            var largest = 1;

            for (fields) |capture|
                if (largest < @alignOf(capture.type)) {
                    largest = @alignOf(capture.type);
                };

            return largest;
        }
    };
}
