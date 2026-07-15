components: []const type = &.{},
tags: []const type = &.{},

const Self = @This();

pub fn eql(self: Self, other: Self) bool {
    if (!@inComptime()) @compileError("Must be called in comptime.");

    if (self.components.len != other.components.len or self.tags.len != other.tags.len) return false;

    outer: for (self.components) |Component| {
        for (other.components) |OthersComponent| {
            if (Component == OthersComponent) continue :outer;
        }

        return false;
    }

    outer: for (self.tags) |Tag| {
        for (other.tags) |OthersTag| {
            if (Tag == OthersTag) continue :outer;
        }

        return false;
    }

    return true;
}

pub fn orderEql(self: Self, other: Self, @"type": enum { component, tag }) bool {
    if (!@inComptime()) @compileError("Must be called in comptime.");

    const field = switch (@"type") {
        .component => "components",
        .tags => "tags",
    };

    if (@field(self, field).len != @field(other, field).len) return false;

    for (0..@field(self, field).len) |i|
        if (@field(self, field)[i] != @field(other, field)[i]) return false;

    return true;
}
