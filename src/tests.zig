// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;

const toposort = @import("toposort.zig");
const TopoSort = toposort.TopoSort;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};


// N - number of nodes, B - dependency branching factor, M - max_range flag, R - repeats
pub fn benchmark(N: usize, B: usize, comptime M: bool, comptime R: usize,
                 options: struct {
                     add: bool = false,
                     sort: bool = false,
                     total: bool = true, }) !void {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // Frees all allocated memory at once
    const allocator = arena.allocator();

    const T = u32;

    var add_times:  [R]Timing = [1]Timing{ .{} } ** R;
    var sort_times: [R]Timing = [1]Timing{ .{} } ** R;
    const list = try gen_int_items(N, T, allocator);

    for (0..R) |i| {
        var tsort =
            if (M) try TopoSort(T).init(allocator, .{ .max_range = N })
            else try TopoSort(T).init(allocator, .{});
        defer tsort.deinit();

        const start1 = nanoTimestamp();
        const batch: usize = N/B-1;
        for (0..batch) |b| {
            const base = b * B;
            for (1..B) |j| {
                try tsort.add(list.items[base], list.items[base + j]);
            }
            try tsort.add(list.items[base], list.items[base + B]);  // chain to next set.
        }
        add_times[i] = .{ .n = N, .start_ns = start1, .end_ns = nanoTimestamp() };

        const start2 = std.time.nanoTimestamp();
        _ = try tsort.sort();
        sort_times[i] = .{ .n = N, .start_ns = start2, .end_ns = nanoTimestamp() };
    }

    const add_total = compute_total(N, B, R, add_times);
    const sort_total = compute_total(N, B, R, sort_times);
    var total = compute_total(N, B, R, sort_times);
    total.add(add_total);

    if (options.add)    try add_total.print("Add dep");
    if (options.sort)   try sort_total.print("Sort");
    if (options.total)  try total.print("Add + Sort");
}


fn gen_int_items(N: usize, comptime T: type, allocator: Allocator) !ArrayList(T) {
    var list = ArrayList(T).init(allocator);
    for (0..N) |num| {
        try list.append(@intCast(num));
    }
    return list;
}


const NS_TO_MS = 1000 * 1000;

const Timing = struct {

    n:          usize = 0,
    start_ns:   i128 = 0,
    end_ns:     i128 = 0,

    fn elapsed_ns(self: Timing) i128 { return self.end_ns - self.start_ns; }
    fn elapsed_ms(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), NS_TO_MS); }
    fn nps(self: Timing) i128 { return @divTrunc(self.n * NS_TO_MS * 1000, self.elapsed_ns()); }
    fn ns_per_item(self: Timing) i128 { return @divTrunc(self.elapsed_ns(), self.n); }
    fn print(self: Timing, title: []const u8) void {
        std.debug.print("{s:11} {} nodes {} links.  Time: {}ms, {} nodes/s, {} ns/node\n",
                        .{title, self.n, self.b, self.elapsed_ms(), self.nps(), self.ns_per_item() });
    }

};

const TimeTotal = struct {
    n:          usize = 0,
    b:          usize = 0,
    repeat:     usize = 0,
    total:      usize = 0,
    elapsed_ns: i128 = 0,

    fn elapsed_ms(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ns, NS_TO_MS); }
    fn ms_per_n(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ms(), self.repeat); }
    fn nps(self: TimeTotal) i128 { return @divTrunc(self.total * NS_TO_MS * 1000, self.elapsed_ns); }
    fn ns_per_item(self: TimeTotal) i128 { return @divTrunc(self.elapsed_ns, self.total); }
    fn print(self: TimeTotal, title: []const u8) !void {
        var buf1: [128]u8 = undefined;
        var buf2: [128]u8 = undefined;
        var buf3: [128]u8 = undefined;
        var buf4: [128]u8 = undefined;
        const str1 = try fmtInt(i128, self.elapsed_ms(), 6, &buf1);
        const str2 = try fmtInt(i128, self.ms_per_n(), 5, &buf2);
        const str3 = try fmtInt(i128, self.nps(), 9, &buf3);
        const str4 = try fmtInt(i128, self.ns_per_item(), 6, &buf4);
        std.debug.print("{s:11} {:8} nodes {:6} links, repeat{: >2}, time:{s}ms,{s} nodes/s,{s} ns/node.\n",
                        .{title, self.n, self.b, self.repeat, str2, str3, str4 });
        _=str1;
        // std.debug.print("{s:11} {:8} nodes {:5} links, repeat {: >2}, total time:{s}ms, time:{s}ms,{s} nodes/s,{s} ns/node.\n",
        //                 .{title, self.n, self.b, self.repeat, str1, str2, str3, str4 });
    }

    fn add(self: *TimeTotal, from: TimeTotal) void {
        self.total += from.total;
        self.elapsed_ns += from.elapsed_ns;
    }
};

fn compute_total(N: usize, B: usize, comptime R: usize, times: [R]Timing) TimeTotal {
    var total: TimeTotal = .{ .n = N, .b = B, };
    var max: i128 = times[0].elapsed_ns();
    var max_i: usize = 0;

    for (1..R)|i| {
        if (max < times[i].elapsed_ns()) {
            max = times[i].elapsed_ns();
            max_i = i;
        }
    }
    for (0..R)|i| {
        if (R > 1 and i == max_i) continue;     // throw away the max entry.
        total.repeat += 1;
        total.total += times[i].n;
        total.elapsed_ns += times[i].elapsed_ns();
    }

    return total;
}

pub fn fmtInt(comptime T: type, num: T, width: usize, buf: []u8) ![]u8 {
    const str = try std.fmt.bufPrint(buf, "{[value]: >[width]}", .{.value = num, .width = width});
    std.mem.replaceScalar(u8, str, '+', ' ');   // get rid of the positive sign
    return str;
}

