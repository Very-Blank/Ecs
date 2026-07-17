const std = @import("std");
const ecs = @import("ecs.zig");

const Template = @import("Template.zig");

pub fn Registry(comptime IDType: type, comptime @"type": enum { component, tag }, comptime templates: []const Template) type {
    const field = switch (@"type") {
        .component => "components",
        .tag => "tags",
    };

    ok: {
        switch (@typeInfo(IDType)) {
            .@"enum" => |@"enum"| if (!@"enum".is_exhaustive or @typeInfo(@"enum".tag_type) == .int) break :ok,
            else => {},
        }

        @compileError("Registery IDType has to be a non exhaustive enum.");
    }

    const len = length: {
        var len: usize = 0;

        for (0..templates.len) |i| {
            outer: for (@field(templates[i], field)) |NewItem| {
                for (0..i) |j| {
                    for (@field(templates[j], field)) |OldItem| {
                        if (OldItem == NewItem) continue :outer;
                    }
                }

                len += 1;
            }
        }

        break :length len;
    };

    return struct {
        pub const Bitset: type = std.bit_set.StaticBitSet(len);

        pub const Iterator = struct {
            index: u32,
            iterator: Bitset.Iterator(.{}),

            pub inline fn init(set: Bitset) Iterator {
                return .{
                    .index = 0,
                    .iterator = set.iterator(.{}),
                };
            }

            pub inline fn next(self: *Iterator) ?struct {
                index: u32,
                id: IDType,
            } {
                if (self.iterator.next()) |capture| {
                    defer self.index += 1;

                    return .{
                        .index = self.index,
                        .id = @enumFromInt(capture),
                    };
                }

                return null;
            }
        };

        pub const types: [len]type = init: {
            var new_types: [len]type = undefined;

            var i = 0;

            for (templates) |template| {
                outer: for (@field(template, field)) |T| {
                    for (0..i) |j| {
                        if (T == new_types[j]) continue :outer;
                    }

                    if (len <= i) @compileError("Length calculation logic incorrect.");

                    new_types[i] = T;
                    i += 1;
                }
            }

            break :init new_types;
        };

        pub const sizes: switch (@"type") {
            .component => [len]usize,
            .tag => void,
        } = switch (@"type") {
            .component => init: {
                var new_sizes: [len]usize = .{0} ** len;
                for (types, 0..) |Item, i| {
                    new_sizes[i] = @sizeOf(Item);
                }

                break :init new_sizes;
            },
            .tag => {},
        };

        pub const bitsets: [templates.len]Bitset = init: {
            var new_bitsets: [templates.len]Bitset = .{Bitset.empty} ** templates.len;

            for (templates, 0..) |template, i| {
                new_bitsets[i] = bitset(@field(template, field));
            }

            break :init new_bitsets;
        };

        pub fn bitset(comptime included: []const type) Bitset {
            if (!@inComptime()) @compileError("Must be called in comptime.");

            var new_bitset: Bitset = .empty;

            for (included) |Item| {
                const index = @intFromEnum(id(Item));

                if (new_bitset.isSet(index)) {
                    @compileError(std.fmt.comptimePrint(
                        "{s} registery had two of the same item named: {s}, which is not allowed.",
                        .{ if (@"type" == .component) "Component" else "Tags", @typeName(Item) },
                    ));
                }

                new_bitset.set(index);
            }

            return new_bitset;
        }

        pub fn id(comptime Item: type) IDType {
            if (!@inComptime()) @compileError("Must be called in comptime.");

            for (types, 0..) |Existing, i| {
                if (Existing == Item) {
                    return @enumFromInt(i);
                }
            }

            @compileError(std.fmt.comptimePrint(
                "{s} registery was given item named: {s}, which was not known by the registery.\nMeaning it wasn't in any of the given templates.",
                .{ if (@"type" == .component) "Component" else "Tags", @typeName(Item) },
            ));
        }
    };
}
