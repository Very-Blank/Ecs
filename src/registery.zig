const std = @import("std");
const ecs = @import("ecs.zig");
const Template = @import("Template.zig");

pub fn Registry(comptime templates: []const Template, comptime field: []const u8) type {
    const len = length: {
        var count: usize = 0;

        for (templates) |template| {
            count += @field(template, field).len;
        }

        for (templates, 0..) |template, i| {
            item_iterator: for (@field(template, field)) |new_item| {
                for (0..i) |j| {
                    for (@field(templates[j], field)) |old_item| {
                        if (old_item == new_item) continue :item_iterator;
                    }
                }

                // NOTE: Each template should only have one of each component or tag.
                next_template: for (i + 1..templates.len) |j| {
                    for (@field(templates[j], field)) |next_item| {
                        if (new_item == next_item) {
                            count -= 1;
                            continue :next_template;
                        }
                    }
                }
            }
        }

        break :length count;
    };

    return struct {
        pub const types: [len]type = init: {
            var init_types: [len]type = undefined;
            var i: usize = 0;

            for (templates) |template| {
                inner: for (@field(template, field)) |@"type"| {
                    for (0..i) |j| {
                        if (init_types[j] == @"type") continue :inner;
                    }

                    init_types[i] = @"type";
                    i += 1;
                }
            }

            if (i != init_types.len) @compileError("The calculated count of unique " ++ field ++ " was incorrect.");
            break :init init_types;
        };

        pub const Bitset = std.bit_set.StaticBitSet(len);

        pub fn bitset(comptime included_types: []const type) Bitset {
            var new_bitset: Bitset = .empty;

            outer: for (included_types) |@"type"| {
                for (types, 0..) |existing_type, i| {
                    if (existing_type == @"type") {
                        if (new_bitset.isSet(i)) {
                            @compileError(.{std.ascii.toUpper(field[0])} ++ field[1..field.len] ++ " had two of the same " ++ field[0 .. field.len - 1] ++ " " ++ @typeName(@"type") ++ ", Which is not allowed.");
                        }

                        new_bitset.set(i);
                        continue :outer;
                    }
                }

                @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(@"type") ++ ", that wasn't known by the ECS.");
            }

            return new_bitset;
        }

        pub fn id(comptime @"type": type) usize {
            for (types, 0..) |existing_component, i| {
                if (existing_component == @"type") {
                    return i;
                }
            }

            @compileError("Was given a " ++ field[0 .. field.len - 1] ++ ": " ++ @typeName(@"type") ++ ", that wasn't known by the ECS.");
        }
    };
}
