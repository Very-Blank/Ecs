const typeId = @import("typeId.zig").typeId;

const Component = struct {
    size: usize,
    alignment: usize,
    typeId: u64,
    pub fn new(comptime T: type) Component {
        return .{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .typeId = typeId(T),
        };
    }
};
