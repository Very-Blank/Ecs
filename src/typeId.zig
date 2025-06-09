pub const TypeId = *const struct {
    _: u8,
};

pub inline fn get(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}
