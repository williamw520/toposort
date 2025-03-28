
const std = @import("std");
const Allocator = std.mem.Allocator;


pub const BitArray = struct {
    const Self = @This();
    const W = u64;          // word type.
    const word_bytes = @sizeOf(W);

    count:      usize,
    data:       []W,

    pub fn init(allocator: Allocator, num_of_bits: usize) !Self {
        const words = (num_of_bits + word_bytes - 1) / word_bytes;
        const data = try allocator.alloc(W, words);
        @memset(data, 0);
        return .{ .count = num_of_bits, .data = data, };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.data);
    }

    pub fn get(self: Self, pos: usize) bool {
        const index = pos / word_bytes;
        const bit   = pos % word_bytes;
        const mask  = @shlExact(@as(u64, 1), @as(u6, @intCast(bit)));
        return self.data[index] & mask != 0;
    }

    pub fn set(self: *Self, pos: usize, flag: bool) void {
        if (flag) { self.on(pos); } else { self.off(pos); }
    }

    pub fn on(self: *Self, pos: usize) void {
        const index = pos / word_bytes;
        const bit   = pos % word_bytes;
        const mask  = @shlExact(@as(u64, 1), @as(u6, @intCast(bit)));
        self.data[index] = self.data[index] | mask;
    }

    pub fn off(self: *Self, pos: usize) void {
        const index = pos / word_bytes;
        const bit   = pos % word_bytes;
        const mask  = @shlExact(@as(u64, 1), @as(u6, @intCast(bit)));
        self.data[index] = self.data[index] & ~mask;
    }

    pub fn set_all(self: *Self) void {
        @memset(self.data, 0xFF);   // This sets all bits in u64.
    }

    pub fn clear_all(self: *Self) void {
        @memset(self.data, 0);
    }

    pub fn dump(self: Self) void {
        for (0..self.count) |i| {
            const b: usize = if (self.get(i)) 1 else 0;
            std.debug.print("{}", .{b});
            if ((i + 1) % 8 == 0) std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
    }
    
};

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var ba1 = try BitArray.init(allocator, 96);
    defer ba1.deinit(allocator);

    ba1.dump();

    var pos: usize = 0;

    for (0..ba1.count)|i| {
        try std.testing.expect(ba1.get(i) == false);
    }

    ba1.set(pos, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.set(pos + 1, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos or i == pos + 1) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.set(pos, false);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos + 1) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.set_all();
    ba1.dump();
    for (0..ba1.count)|i| {
        try std.testing.expect(ba1.get(i) == true);
    }

    ba1.clear_all();
    ba1.dump();
    for (0..ba1.count)|i| {
        try std.testing.expect(ba1.get(i) == false);
    }
    
    ba1.clear_all();
    pos = 7;

    ba1.set(pos, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.set(pos + 1, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos or i == pos + 1) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.clear_all();
    pos = 63;

    ba1.set(pos, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

    ba1.set(pos + 1, true);
    ba1.dump();
    for (0..ba1.count)|i| {
        if (i == pos or i == pos + 1) {
            try std.testing.expect(ba1.get(i) == true);
        } else {
            try std.testing.expect(ba1.get(i) == false);
        }
    }

}


