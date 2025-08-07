const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const helper = @import("helper.zig");

pub const EntityType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) EntityType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": EntityType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const GenerationType = enum(u32) {
    _,

    pub inline fn make(@"u32": u32) GenerationType {
        return @enumFromInt(@"u32");
    }

    pub inline fn value(@"enum": GenerationType) u32 {
        return @intFromEnum(@"enum");
    }
};

pub const EntityPointer = struct {
    entity: EntityType,
    generation: GenerationType,
};

pub const ArchetypePointer = struct {
    archetype: ArchetypeType,
    generation: GenerationType,
};

pub fn Arhetypes(comptime T: type) type {
    const @"struct": std.builtin.Type.Struct = helper.getTuple(T);
    var new_fields: [@"struct".fields.len]std.builtin.Type.StructField = undefined;

    for (@"struct".fields, 0..) |field, i| {
        new_fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = Archetype(field.type),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Archetype(field.type)),
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
}

pub fn Ecs(comptime archetypesTuple: type) type {
    const archetypesInfo = helper.getTuple(archetypesTuple);

    return struct {
        archetypes: Arhetypes(archetypesTuple),
        allocator: std.mem.Allocator,
        // entityMap: std.AutoArrayHashMapUnmanaged(EntityType, ArchetypePointer),
        // archetypeMap: std.AutoArrayHashMapUnmanaged(Bitset, ArchetypeType),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = .{
                .archetypes = undefined,
                .allocator = allocator,
            };

            inline for (archetypesInfo.fields, 0..) |field, i| {
                result.archetypes[i] = Archetype(field.type).init(" ", Bitset.initEmpty());
            }

            return result;
        }

        pub fn deinit(self: *Self) void {
            inline for (0..archetypesInfo.fields.len) |i| {
                self.archetypes[i].deinit(self.allocator);
            }
        }

        pub fn createEntity(self: *Self, comptime T: type, components: T) EntityPointer {
            // new entity
            inline for (archetypesInfo.fields, 0..) |field, i| {
                if (field.type == T) {
                    self.archetypes[i].append(EntityType.make(0), components, self.allocator) catch unreachable;

                    return EntityPointer{ .entity = EntityType.make(0), .generation = .make(0) };
                }
            }

            @compileError("ARCHE TYPE NOT EXIST");
        }
    };
}
