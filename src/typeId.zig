pub fn typeId(comptime T: type) u64 {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };

    return @intFromPtr(&H.byte);
}
