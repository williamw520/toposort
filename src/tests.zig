const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const toposort = @import("toposort.zig");
const TopoSort = toposort.TopoSort;

const NS_TO_MS = 1000 * 1000;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


pub fn test1() !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;
    var tsort = try TopoSort(T).init(allocator, .{});
    defer tsort.deinit();

    const N = 1000000;
    std.debug.print("test {} items.\n", .{N});
    const list = try gen_int_items(N, T, allocator);
    {
        const start_ns = std.time.nanoTimestamp();
        for (0..N-1) |idx| {
            try tsort.add_dependency(list.items[idx], list.items[idx+1]);
        }
        const end_ns = std.time.nanoTimestamp();
        const elapsed_ms =  @divTrunc((end_ns - start_ns), NS_TO_MS);
        std.debug.print("Add dependency {} pairs. Time: {}ms\n", .{N, elapsed_ms});
    }

    {
        const start_ns = std.time.nanoTimestamp();
        const result = try tsort.sort();
        _=result;
        const end_ns = std.time.nanoTimestamp();
        const elapsed_ms =  @divTrunc((end_ns - start_ns), NS_TO_MS);
        std.debug.print("Sort {} pairs. Time: {}ms\n", .{N, elapsed_ms});
    }

}

fn gen_int_items(comptime N: usize, comptime T: type, allocator: Allocator) !ArrayList(T) {
    var list = ArrayList(T).init(allocator);
    for (0..N) |num| {
        try list.append(@intCast(num));
    }
    return list;
}

fn bench_msg(comptime fmt: []const u8, args: anytype, time: *i128) void {
    const now = std.time.nanoTimestamp();
    const elapsed = now - time.*;
    std.debug.print("{}: ", .{ elapsed });
    std.debug.print(fmt, args);
    time.* = now;
}


