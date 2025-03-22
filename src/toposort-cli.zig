
const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();
// const g_allocator = std.heap.page_allocator;
// const g_allocator = std.testing.allocator;

const TopoSort = toposort.TopoSort;


pub fn main() !void {
    std.debug.print("\n", .{});

    {
        // var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
        // const stdout = bw.writer();

        var args = try CmdArgs.parse(g_allocator);
        defer args.deinit();
        std.debug.print("data_file: {s}, out_file: {s}, is_int: {}, is_parallel: {}\n", .{ args.data_file, args.out_file, args.is_int, args.is_parallel });

        if (args.is_int) {
            const T = u32;
            const tsort = try TopoSort(T).init(g_allocator);
            defer tsort.deinit();
            try readData(T, args.data_file, tsort);
            try tsort.process();
        } else {
            const T = []const u8;
            const tsort = try TopoSort(T).init(g_allocator);
            defer tsort.deinit();
            try readData(T, args.data_file, tsort);
            try tsort.process();
        }
        // try bw.flush();
    }

    if (gpa.detectLeaks()) {
        std.debug.print("🚨 Memory leak detected!\n", .{});
    } else {
        std.debug.print("✅ No memory leaks!\n", .{});
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
        const dependent, const required = parseLine(line_buf.items);
        if (T == u32) {
            const dep_num = try std.fmt.parseInt(u32, dependent, 10);
            const req_num = try std.fmt.parseInt(u32, required, 10);
            try tsort.add_dependency(req_num, dep_num);
        } else {
            try tsort.add_dependency(required, dependent);
        }
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line_buf.items.len > 0) {
                const dependent, const required = parseLine(line_buf.items);
                if (T == u32) {
                    const dep_num = try std.fmt.parseInt(u32, dependent, 10);
                    const req_num = try std.fmt.parseInt(u32, required, 10);
                    try tsort.add_dependency(req_num, dep_num);
                } else {
                    try tsort.add_dependency(required, dependent);
                }
            }
        },
        else => return err, // Propagate error
    }
}

fn parseLine(line: []const u8) struct { []const u8, []const u8 } {
    var tokens = std.mem.tokenizeScalar(u8, line, ':');
    const term1 = tokens.next() orelse "";      // depending item
    const term2 = tokens.next() orelse "";      // required/leading item
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
