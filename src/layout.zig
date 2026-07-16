const std = @import("std");

pub const Region = struct {
    name: []const u8,
    type_size: comptime_int,
    aligment: comptime_int,
    count: comptime_int = 1,
};

pub fn Layout(
    comptime regions: []const Region,
) type {
    for (0..regions.len) |i| {
        for (i + 1..regions.len) |j| {
            if (std.mem.eql(u8, regions[i].name, regions[j].name))
                @compileError(std.fmt.comptimePrint(
                    "Region name: {s} is used twice at index {any} and {any}.",
                    .{ regions[i].name, i, j },
                ));
        }
    }

    if (1 < regions.len) {
        var offset = 0;
        for (regions) |region| {
            if (-offset & (region.aligment - 1) != 0)
                @compileError(std.fmt.comptimePrint(
                    "Region {s} needs {any} bytes of padding before it.",
                    .{ region.name, -offset & (region.aligment - 1) },
                ));

            offset += region.type_size * region.count;
        }
    }

    return struct {
        pub inline fn regionStart(comptime name: []const u8) comptime_int {
            return comptime init: {
                var offset: comptime_int = 0;

                for (regions) |region| {
                    if (std.mem.eql(u8, name, region.name)) break :init offset;

                    offset += region.type_size * region.count;
                }

                @compileError(std.fmt.comptimePrint("Field {s} doesn't exist.", .{name}));
            };
        }

        pub inline fn regionEnd(comptime name: []const u8) comptime_int {
            return comptime init: {
                var offset: comptime_int = 0;

                for (regions) |region| {
                    offset += region.type_size * region.count;

                    if (std.mem.eql(u8, name, region.name)) break :init offset;
                }

                @compileError(std.fmt.comptimePrint("Field {s} doesn't exist.", .{name}));
            };
        }

        pub inline fn regionSize(comptime name: []const u8) comptime_int {
            return comptime init: {
                for (regions) |region| {
                    if (std.mem.eql(u8, name, region.name)) break :init region.type_size * region.count;
                }

                @compileError(std.fmt.comptimePrint("Field {s} doesn't exist.", .{name}));
            };
        }

        pub inline fn size() comptime_int {
            return comptime init: {
                var sum = 0;

                for (regions) |region|
                    sum += region.type_size * region.count;

                break :init sum;
            };
        }

        pub inline fn alignment() comptime_int {
            return comptime init: {
                var largest = 1;

                for (regions) |region|
                    if (largest < region.aligment) {
                        largest = region.aligment;
                    };

                break :init largest;
            };
        }
    };
}
