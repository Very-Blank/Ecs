components: []const type = &.{},
tags: []const type = &.{},

const Self = @This();

pub fn eql(self: *const Self, other: Self) bool {
    if (self.components.len != other.components.len) return false;

    outer: for (self.components) |component| {
        for (other.components) |component2| {
            if (component == component2) continue :outer;
        }

        return false;
    }

    if (self.tags.len != other.tags.len) return false;

    outer: for (self.tags) |tag| {
        for (other.tags) |tag2| {
            if (tag == tag2) continue :outer;
        }

        return false;
    }

    return true;
}

pub fn orderEql(self: *const Self, other: Self, field: []const u8) bool {
    if (@field(self, field).len != @field(other, field).len) return false;

    for (0..@field(self, field).len) |i|
        if (@field(self, field)[i] != @field(other, field)[i]) return false;

    return true;
}
