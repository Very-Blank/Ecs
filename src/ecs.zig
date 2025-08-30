const std = @import("std");

const ULandType = @import("uLandType.zig").ULandType;

const Bitset = @import("componentManager.zig").Bitset;

const Archetype = @import("archetype.zig").Archetype;
const ArchetypeType = @import("archetype.zig").ArchetypeType;
const RowType = @import("archetype.zig").RowType;

const Iterator = @import("iterator.zig").Iterator;
const TupleIterator = @import("iterator.zig").TupleIterator;

const compStruct = @import("comptimeStruct.zig");
const TupleOfArrayLists = @import("comptimeStruct.zig").TupleOfArrayLists;
const TupleOfBuffers = @import("comptimeStruct.zig").TupleOfBuffers;

pub const Template: type = struct { components: type, tags: type };
pub const EmptyTags: type = struct {};

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

pub fn Arhetypes(comptime templates: []const Template) type {
    var newFields: [templates.len]std.builtin.Type.StructField = undefined;

    inline for (templates, 0..) |template, i| {
        newFields[i] = std.builtin.Type.StructField{
            .name = compStruct.itoa(i),
            .type = Archetype(template),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Archetype(template)),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &newFields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

// FIXME: generation isn't hadeled correctly currently all new entitys are set to zero even if they existed before.
pub fn Ecs(comptime templates: []const Template) type {
    return struct {
        archetypes: Arhetypes(templates),
        entityToArchetypeMap: std.AutoArrayHashMapUnmanaged(EntityType, ArchetypePointer),
        unusedEntitys: std.ArrayListUnmanaged(EntityType),
        destroyedEntitys: std.ArrayListUnmanaged(EntityType),
        entityCount: u32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .archetypes = init: {
                    var archetypes: Arhetypes(templates) = undefined;
                    inline for (0..archetypes.len) |i| {
                        archetypes[i] = .init;
                    }

                    break :init archetypes;
                },
                .entityToArchetypeMap = .empty,
                .unusedEntitys = .empty,
                .destroyedEntitys = .empty,
                .entityCount = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (0..templates.len) |i| {
                self.archetypes[i].deinit(self.allocator);
            }

            self.entityToArchetypeMap.deinit(self.allocator);
            self.unusedEntitys.deinit(self.allocator);
            self.destroyedEntitys.deinit(self.allocator);
        }

        pub fn entityIsValid(self: *Self, entityPtr: EntityPointer) bool {
            if (self.entityToArchetypeMap.get(entityPtr.entity)) |archetypePtr| {
                if (archetypePtr.generation == entityPtr.generation) {
                    return true;
                }
            }

            return false;
        }

        pub fn createEntity(self: *Self, comptime template: Template, components: template.components) EntityPointer {
            const newEntity = init: {
                if (self.unusedEntitys.items.len > 0) {
                    break :init self.unusedEntitys.pop().?;
                }

                self.entityCount += 1;
                break :init EntityType.make(self.entityCount - 1);
            };

            inline for (templates, 0..) |temp, i| {
                if (temp.components == template.components and temp.tags == template.tags) {
                    self.archetypes[i].append(newEntity, components, self.allocator) catch unreachable;
                    self.entityToArchetypeMap.put(self.allocator, newEntity, .{ .archetype = ArchetypeType.make(@intCast(i)), .generation = .make(0) }) catch unreachable;

                    return EntityPointer{ .entity = newEntity, .generation = .make(0) };
                }
            }

            @compileError("Supplied template, didn't have a corresponding archetype");
        }

        pub fn destroyEntity(self: *Self, entity: EntityType) void {
            self.destroyedEntitys.append(self.allocator, entity) catch unreachable;
        }

        pub fn clearDestroyedEntitys(self: *Self) void {
            for (self.destroyedEntitys.items) |entity| {
                const archetypePtr = self.entityToArchetypeMap.get(entity).?;
                try self.archetypes[archetypePtr.archetype.value()].remove(entity, self.allocator) catch unreachable;
            }
        }

        pub fn getArchetype(self: *Self, comptime template: Template) *Archetype(template) {
            inline for (0..self.archetypes.len) |i| {
                if (template.components == self.archetypes[i].componentsType and self.archetypes[i].tagsType == template.tags) {
                    return &self.archetypes[i];
                }
            }

            @compileError("Supplied template, didn't have a corresponding archetype");
        }

        pub fn isArchetypeMatch(comptime template: Template, comptime includeTemplate: Template, comptime excludeTemplate: Template) bool {
            const componentsTuple = compStruct.getTuple(template.components);
            const tagsTuple = compStruct.getTupleAllowEmpty(template.tags);

            const iComponentsTuple = compStruct.getTuple(includeTemplate.components);
            const iTagsTuple = compStruct.getTupleAllowEmpty(includeTemplate.tags);

            const eComponentsTuple = compStruct.getTupleAllowEmpty(excludeTemplate.components);
            const etagsTuple = compStruct.getTupleAllowEmpty(excludeTemplate.tags);

            outer: inline for (iComponentsTuple.fields) |iField| {
                inline for (componentsTuple.fields) |cField| {
                    if (iField.type == cField.type) continue :outer;
                }

                return false;
            }

            outer: inline for (iTagsTuple.fields) |iField| {
                inline for (tagsTuple.fields) |cField| {
                    if (iField.type == cField.type) continue :outer;
                }

                return false;
            }

            inline for (eComponentsTuple.fields) |eField| {
                inline for (componentsTuple.fields) |cField| {
                    if (eField.type == cField.type) return false;
                }
            }

            inline for (etagsTuple.fields) |eField| {
                inline for (tagsTuple.fields) |cField| {
                    if (eField.type == cField.type) return false;
                }
            }

            return true;
        }

        // fn getInclude(comptime T: type) type {
        //     var new_fields: [1]std.builtin.Type.StructField = std.builtin.Type.StructField{
        //         .name = "0",
        //         .type = []T,
        //         .default_value_ptr = null,
        //         .is_comptime = false,
        //         .alignment = @alignOf([]T),
        //     };
        //
        //     return @Type(.{
        //         .@"struct" = .{
        //             .layout = .auto,
        //             .fields = &new_fields,
        //             .decls = &.{},
        //             .is_tuple = true,
        //         },
        //     });
        // }

        pub fn getIterator(self: *Self, comptime component: type, comptime tags: type, comptime exclude: Template) ?Iterator(component) {
            comptime {
                // FIXME:: Add a check that there is no crossover with include and exclude
                if (@sizeOf(component) == 0) @compileError("Tag was given instead of a component.");
                const maxSize = size: {
                    var size: usize = 0;
                    for (templates) |template| {
                        if (isArchetypeMatch(template, .{ .components = struct { component }, .tags = tags }, exclude)) size += 1;
                    }

                    break :size size;
                };

                if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
            }

            var componentArrays: std.ArrayListUnmanaged([]component) = .empty;
            errdefer componentArrays.deinit(self.allocator);

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            inline for (templates, 0..) |template, i| {
                if (comptime isArchetypeMatch(template, .{ .components = struct { component }, .tags = tags }, exclude)) {
                    const array = self.archetypes[i].getComponentArray(component);
                    if (array.len > 0) {
                        componentArrays.append(self.allocator, array) catch unreachable;
                        entitys.append(self.allocator, self.archetypes[i].getEntitys()) catch unreachable;
                    }
                }
            }

            if (componentArrays.items.len == 0) {
                return null;
            }

            return Iterator(component).init(componentArrays.toOwnedSlice(self.allocator) catch unreachable, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }

        pub fn getTupleIterator(self: *Self, comptime template: Template, comptime excludeTemplate: Template) ?TupleIterator(template.components) {
            comptime {
                // FIXME:: Add a check that there is no crossover with include and exclude
                const maxSize = size: {
                    var size: usize = 0;
                    for (templates) |temp| {
                        if (isArchetypeMatch(temp, template, excludeTemplate)) size += 1;
                    }

                    break :size size;
                };

                if (maxSize == 0) @compileError("No matching archetypes with the supplied include and exclude.");
            }

            const components = compStruct.getTuple(template.components);

            var tupleOfArrayList: TupleOfArrayLists(template.components) = init: {
                var tupleOfArrayList: TupleOfArrayLists(template.components) = undefined;
                inline for (0..components.fields.len) |i| {
                    tupleOfArrayList[i] = .empty;
                }

                break :init tupleOfArrayList;
            };

            errdefer {
                inline for (0..tupleOfArrayList.len) |i| {
                    tupleOfArrayList[i].deinit(self.allocator);
                }
            }

            var entitys: std.ArrayListUnmanaged([]EntityType) = .empty;
            errdefer entitys.deinit(self.allocator);

            outer: inline for (templates, 0..) |temp, i| {
                if (comptime isArchetypeMatch(temp, template, excludeTemplate)) {
                    inline for (components.fields, 0..) |component, j| {
                        const array = self.archetypes[i].getComponentArray(component.type);
                        if (array.len > 0) {
                            tupleOfArrayList[j].append(self.allocator, array) catch unreachable;
                            if (comptime j == 0) entitys.append(self.allocator, self.archetypes[i].getEntitys()) catch unreachable;
                        } else {
                            continue :outer;
                        }
                    }
                }
            }

            if (tupleOfArrayList[0].items.len == 0) {
                return null;
            }

            const tupleOfBuffers: TupleOfBuffers(template.components) = init: {
                var tupleOfBuffers: TupleOfBuffers(template.components) = undefined;
                inline for (0..components.fields.len) |i| {
                    tupleOfBuffers = tupleOfArrayList[i].toOwnedSlice(self.allocator) catch unreachable;
                }

                break :init tupleOfBuffers;
            };

            errdefer {
                inline for (tupleOfBuffers) |buffer| {
                    self.allocator.free(buffer);
                }
            }

            return TupleIterator(template).init(tupleOfBuffers, entitys.toOwnedSlice(self.allocator) catch unreachable, self.allocator);
        }
    };
}
