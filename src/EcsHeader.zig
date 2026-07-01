entity: packed struct(u64) {
    count: u32,
    capacity: u32,
},
padding: u64,

const Self = @This();
