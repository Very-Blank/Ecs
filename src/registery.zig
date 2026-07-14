const std = @import("std");
const ecs = @import("ecs.zig");
const Template = @import("Template.zig");

pub fn Registry(comptime IDType: type, comptime templates: []const Template, comptime @"type": enum { component, tag }) type {
    const field = if (@"type" == .component) "component" else "tag";

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
        pub const types: [len]type = init: {
            var new_types: [len]type = undefined;

            var i = 0;

            for (templates) |template| {
                inner: for (@field(template, field)) |T| {
                    for (0..i) |j| {
                        if (T == new_types[j]) continue :inner;
                    }

                    if (len <= i) @compileError("Length calculation logic incorrect.");

                    new_types[i] = T;
                    i += 1;
                }
            }

            break :init new_types;
        };

        pub const Bitset = std.bit_set.StaticBitSet(len);

        pub fn bitset(comptime included_types: []const type) Bitset {
            if (!@inComptime()) @compileError("Must be called in comptime.");

            var new_bitset: Bitset = .empty;

            outer: for (included_types) |Item| {
                for (types, 0..) |ExistingItem, i| {
                    if (ExistingItem == Item) {
                        if (new_bitset.isSet(i)) {
                            @compileError(.{std.ascii.toUpper(field[0])} ++ field[1..field.len] ++ " had two of the same " ++ field[0 .. field.len - 1] ++ " " ++ @typeName(@"type") ++ ", Which is not allowed.");
                        }

                        new_bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(@"type") ++ ", that wasn't known by the registery.");
            }

            return new_bitset;
        }

        pub fn id(comptime Item: type) IDType {
            if (!@inComptime()) @compileError("Must be called in comptime.");

            for (types, 0..) |ExistingComponent, i| {
                if (ExistingComponent == Item) {
                    return @enumFromInt(i);
                }
            }

            @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(Item) ++ ", that wasn't known by the registery.");
        }
    };
}
