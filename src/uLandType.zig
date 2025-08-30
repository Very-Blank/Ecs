const TypeID = *const struct {
    _: u8,
};

/// User land type, wrapper around TypeID.
pub const ULandType = struct {
    type: TypeID,

    pub inline fn get(comptime T: type) ULandType {
        return ULandType{
            .type = &struct {
                comptime {
                    _ = T;
                }
                var id: @typeInfo(TypeID).pointer.child = undefined;
            }.id,
        };
    }

    pub inline fn getHash(comptime T: type) u64 {
        return @intFromPtr(get(T).type);
    }

    pub inline fn hash(self: *ULandType) u64 {
        return @intFromPtr(self.type);
    }

    pub inline fn eql(self: *const ULandType, other: ULandType) bool {
        return self.type == other.type;
    }
};
