
const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();
// const g_allocator = std.heap.page_allocator;
// const g_allocator = std.testing.allocator;

const TopoSort = toposort.TopoSort;


pub fn main() !void {
    std.debug.print("\n", .{});

    {
        var args = try CmdArgs.parse(g_allocator);
        defer args.deinit();
        std.debug.print("data_file: {s}, out_file: {s}, is_int: {}, is_parallel: {}\n", .{ args.data_file, args.out_file, args.is_int, args.is_parallel });

        if (args.is_int) {
            const T = u32;
            var tsort = try TopoSort(T).init(g_allocator);
            defer tsort.deinit();
            try readData(T, args.data_file, &tsort);
            const success = try tsort.process();
            std.debug.print("Processing status: {s}\n", .{ if (success) "success" else "error" });

            const result: ArrayList(ArrayList(T)) = tsort.get_sorted_sets();
            std.debug.print("  topological sorted [", .{});
            for (result.items) |list| {
                std.debug.print(" {{ ", .{});
                for (list.items) |item| std.debug.print("{} ", .{item});
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        } else {
            const T = []const u8;
            var tsort = try TopoSort(T).init(g_allocator);
            defer tsort.deinit();
            try readData(T, args.data_file, &tsort);
            const success = try tsort.process();
            std.debug.print("Processing status: {s}\n", .{ if (success) "success" else "error" });

            const result: ArrayList(ArrayList(T)) = tsort.get_sorted_sets();
            std.debug.print("  topological sorted [", .{});
            for (result.items) |list| {
                std.debug.print(" {{ ", .{});
                for (list.items) |item| std.debug.print("{s} ", .{item});
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    } else {
        std.debug.print("No memory leaks!\n", .{});
    }    
}

const CmdArgs = struct {
    arg_itr:        ArgIterator,
    program:        []const u8,
    data_file:      []const u8,
    out_file:       []const u8,
    is_parallel:    bool,
    is_int:     bool,

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

    fn parse(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .data_file = "dep.txt", // default to dependency file in the working dir.
            .out_file = "result.out",
            .is_parallel = false,
            .is_int = false,
        };
        var argv = args.arg_itr;
        args.program = argv.next() orelse "";
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--data")) {
                args.data_file = std.mem.sliceTo(argv.next(), 0) orelse "dep.txt";
            } else if (std.mem.eql(u8, arg, "--out")) {
                args.out_file = std.mem.sliceTo(argv.next(), 0) orelse "result.out";
            } else if (std.mem.eql(u8, arg, "--parallel")) {
                args.is_parallel = true;
            } else if (std.mem.eql(u8, arg, "--int")) {
                args.is_int = true;
            }
        }
        return args;
    }
};

fn readData(comptime T: type, data_file: []const u8, tsort: *TopoSort(T)) !void {
    const file = std.fs.cwd().openFile(data_file, .{ .mode = .read_only }) catch |err| {
        print("Error {} on opening the file: {s}\n", .{err, data_file});
        return err;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();
    var line_buf = std.ArrayList(u8).init(g_allocator);
    defer line_buf.deinit();
    const writer = line_buf.writer();

    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line_buf.clearRetainingCapacity();
        try parseLine(line_buf.items, T, tsort);
    } else |err| switch (err) {
        error.EndOfStream => {  // end of file
            if (line_buf.items.len > 0) {
                try parseLine(line_buf.items, T, tsort);
            }
        },
        else => return err,     // Propagate error
    }
}

fn parseLine(line: []const u8, comptime T: type, tsort: *TopoSort(T)) !void {
    var tokens      = std.mem.tokenizeScalar(u8, line, ':');
    const first     = tokens.next() orelse "";  // depending item
    const dependent = std.mem.trim(u8, first, " \t\r\n");
    if (dependent.len == 0)
        return;
    const dep_num   = if (T == u32) try std.fmt.parseInt(u32, dependent, 10);

    const rest      = tokens.next() orelse "";  // leading/required items
    var rest_tokens = std.mem.tokenizeScalar(u8, rest, ' ');
    while (rest_tokens.next()) |token| {
        const lead  = std.mem.trim(u8, token, " \t\r\n");
        if (T == u32) {
            const lead_num: ?T = if (lead.len == 0) null else try std.fmt.parseInt(u32, lead, 10);
            try tsort.add_dependency(lead_num, dep_num);
        } else {
            const lead_txt: ?T = if (lead.len == 0) null else lead;
            try tsort.add_dependency(lead_txt, dependent);
        }
    }
}

inline fn print(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format, args) catch |err| {
        std.log.err("Error encountered while printing to stdout. Error: {any}", .{err});
    };
}


test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
