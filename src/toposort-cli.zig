
const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();
// const g_allocator = std.heap.page_allocator;

const TopoSort = toposort.TopoSort([]const u8);


pub fn main() !void {
    std.debug.print("\n", .{});
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();

    var args = try CmdArgs.parse(g_allocator);
    defer args.deinit();
    try stdout.print("data_file: {s}, out_file: {s}, is_parallel: {}\n", .{ args.data_file, args.out_file, args.is_parallel });

    const tsort = try TopoSort.init(g_allocator);
    defer tsort.deinit();

    try readData(args.data_file, tsort);

    try bw.flush();
}

const CmdArgs = struct {
    allocator:      Allocator,
    arg_itr:        ArgIterator,
    program:        []const u8,
    data_file:      []const u8,
    out_file:       []const u8,
    is_parallel:    bool,

    fn deinit(self: *CmdArgs) void {
        defer self.arg_itr.deinit();
    }

    fn parse(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .allocator = allocator,
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .data_file = "dep.txt", // default to dependency file in the working dir.
            .out_file = "result.out",
            .is_parallel = false,
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
            }
        }
        return args;
    }
};

fn readData(data_file: []const u8, tsort: *TopoSort) !void {
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
        const dependent, const required = parseLine(line_buf.items);
        try tsort.add(dependent, required);
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line_buf.items.len > 0) {
                const dependent, const required = parseLine(line_buf.items);
                try tsort.add(dependent, required);
            }
        },
        else => return err, // Propagate error
    }
}

fn parseLine(line: []const u8) struct { []const u8, []const u8 } {
    var tokens = std.mem.tokenizeScalar(u8, line, ',');
    const term1 = tokens.next() orelse "";      // depending item
    const term2 = tokens.next() orelse "";      // required item
    const first = std.mem.trim(u8, term1, " \t\r\n");
    const second = std.mem.trim(u8, term2, " \t\r\n");
    
    return .{ first, second };
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
