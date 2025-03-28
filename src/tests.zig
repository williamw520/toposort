const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;

const toposort = @import("toposort.zig");
const TopoSort = toposort.TopoSort;

const NS_TO_MS = 1000 * 1000;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


pub fn benchmark1() !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;
    const N = 1000000;
    std.debug.print("Testing {} items, 1-to-1 chaining dependency.\n", .{N});

    const list = try gen_int_items(N, T, allocator);

    for (0..2) |_| {
        var tsort = try TopoSort(T).init(allocator, .{});
        defer tsort.deinit();

        // Note: add_dependency takes so long is probably because adding item to hashmap.
        const start_ns1 = nanoTimestamp();
        for (0..N-1) |idx| {
            try tsort.add_dependency(list.items[idx], list.items[idx+1]);
        }
        (Timing { .n = N, .start_ns = start_ns1, .end_ns = nanoTimestamp() }).print("Add dependency");

        const start_ns2 = std.time.nanoTimestamp();
        _ = try tsort.sort();
        (Timing { .n = N, .start_ns = start_ns2, .end_ns = nanoTimestamp() }).print("Sort");
    }
}

pub fn benchmark2() !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;
    const N = 1000000;
    std.debug.print("Testing {} items, 1-to-4 chaining dependency.\n", .{N});

    const list = try gen_int_items(N, T, allocator);

    for (0..2) |_| {
        var tsort = try TopoSort(T).init(allocator, .{});
        defer tsort.deinit();

        const start_ns1 = nanoTimestamp();
        for (0..N/4-1) |idx| {
            const i = idx * 4;
            try tsort.add_dependency(list.items[i], list.items[i+1]);
            try tsort.add_dependency(list.items[i], list.items[i+2]);
            try tsort.add_dependency(list.items[i], list.items[i+3]);
            try tsort.add_dependency(list.items[i], list.items[i+4]);   // chain to next set.
        }
        (Timing { .n = N, .start_ns = start_ns1, .end_ns = nanoTimestamp() }).print("Add dependency");

        const start_ns2 = std.time.nanoTimestamp();
        _ = try tsort.sort();
        (Timing { .n = N, .start_ns = start_ns2, .end_ns = nanoTimestamp() }).print("Sort");
    }
}

pub fn benchmark3() !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;
    const N = 1000000;
    std.debug.print("Testing {} items, 1-to-10 chaining dependency.\n", .{N});

    const list = try gen_int_items(N, T, allocator);

    for (0..2) |_| {
        var tsort = try TopoSort(T).init(allocator, .{});
        defer tsort.deinit();

        const start_ns1 = nanoTimestamp();
        for (0..N/10-1) |idx| {
            const i = idx * 10;
            try tsort.add_dependency(list.items[i], list.items[i+1]);
            try tsort.add_dependency(list.items[i], list.items[i+2]);
            try tsort.add_dependency(list.items[i], list.items[i+3]);
            try tsort.add_dependency(list.items[i], list.items[i+4]);
            try tsort.add_dependency(list.items[i], list.items[i+5]);
            try tsort.add_dependency(list.items[i], list.items[i+6]);
            try tsort.add_dependency(list.items[i], list.items[i+7]);
            try tsort.add_dependency(list.items[i], list.items[i+8]);
            try tsort.add_dependency(list.items[i], list.items[i+9]);
            try tsort.add_dependency(list.items[i], list.items[i+10]);  // chain to next set.
        }
        (Timing { .n = N, .start_ns = start_ns1, .end_ns = nanoTimestamp() }).print("Add dependency");

        const start_ns2 = std.time.nanoTimestamp();
        _ = try tsort.sort();
        (Timing { .n = N, .start_ns = start_ns2, .end_ns = nanoTimestamp() }).print("Sort");
    }
}

pub fn benchmark4() !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;
    const N = 1000000;
    std.debug.print("Testing {} items, 1-to-10 chaining dependency, with max_range set.\n", .{N});

    const list = try gen_int_items(N, T, allocator);

    for (0..2) |_| {
        var tsort = try TopoSort(T).init(allocator, .{ .max_range = N });
        defer tsort.deinit();

        const start_ns1 = nanoTimestamp();
        for (0..N/10-1) |idx| {
            const i = idx * 10;
            try tsort.add_dependency(list.items[i], list.items[i+1]);
            try tsort.add_dependency(list.items[i], list.items[i+2]);
            try tsort.add_dependency(list.items[i], list.items[i+3]);
            try tsort.add_dependency(list.items[i], list.items[i+4]);
            try tsort.add_dependency(list.items[i], list.items[i+5]);
            try tsort.add_dependency(list.items[i], list.items[i+6]);
            try tsort.add_dependency(list.items[i], list.items[i+7]);
            try tsort.add_dependency(list.items[i], list.items[i+8]);
            try tsort.add_dependency(list.items[i], list.items[i+9]);
            try tsort.add_dependency(list.items[i], list.items[i+10]);  // chain to next set.
        }
        (Timing { .n = N, .start_ns = start_ns1, .end_ns = nanoTimestamp() }).print("Add dependency");

        const start_ns2 = std.time.nanoTimestamp();
        _ = try tsort.sort();
        (Timing { .n = N, .start_ns = start_ns2, .end_ns = nanoTimestamp() }).print("Sort");
    }
}


fn gen_int_items(comptime N: usize, comptime T: type, allocator: Allocator) !ArrayList(T) {
    var list = ArrayList(T).init(allocator);
    for (0..N) |num| {
        try list.append(@intCast(num));
    }
    return list;
}

const Timing = struct {
    const NS_TO_MS = 1000 * 1000;

    n:          usize,
    start_ns:   i128,
    end_ns:     i128,

    fn elapsed_ns(self: Timing) i128 { return self.end_ns - self.start_ns; }
    fn elapsed_ms(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), Timing.NS_TO_MS); }
    fn nps(self: Timing) i128 { return @divTrunc(self.n * Timing.NS_TO_MS * 1000, self.elapsed_ns()); }
    fn ns_per_item(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), self.n); }
    fn print(self: Timing, title: []const u8) void {
        std.debug.print("{s:16} {} pairs. Time: {}ms, {} N/s, {} ns/item\n",
                        .{title, self.n, self.elapsed_ms(), self.nps(), self.ns_per_item() });
    }

};

