
const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();
// const g_allocator = std.heap.page_allocator;

const TopoSort = toposort.TopoSort;


pub fn main() !void {
    std.debug.print("\n", .{});

    {
        var args = try CmdArgs.parse(g_allocator);
        defer args.deinit();
        std.debug.print("file: {s}, is_int: {}\n", .{ args.data_file, args.is_int });

        const file_data = try read_file(args.data_file);
        defer g_allocator.free(file_data);

        if (args.is_int) {
            const T = usize;
            try process_data(T, file_data);
        } else {
            const T = []const u8;
            try process_data(T, file_data);
        }
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

fn read_file(data_file: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(data_file, .{ .mode = .read_only });
    defer file.close();
    const file_size = (try file.stat()).size;
    const file_data = file.readToEndAlloc(g_allocator, file_size);
    return file_data;
}

fn process_data(comptime T: type, file_data: []const u8) !void {
    var tsort = try TopoSort(T).init(g_allocator);
    defer tsort.deinit();

    var lines = std.mem.tokenizeScalar(u8, file_data, '\n');
    while (lines.next()) |line| {
        try process_line(line, T, &tsort);
    }

    if (try tsort.process()) {
        std.debug.print("Processing succeeded.\n", .{});
        dump_result(T, &tsort);
    } else {
        std.debug.print("Error in processing.\n", .{});
    }
}

fn dump_result(comptime T: type, tsort: *TopoSort(T)) void {
    std.debug.print("Topologically sorted: [", .{});
    const result: ArrayList(ArrayList(T)) = tsort.get_sorted_sets();
    for (result.items) |list| {
        std.debug.print(" {{ ", .{});
        for (list.items) |item| {
            if (T == usize) {
                std.debug.print("{} ", .{item});
            } else {
                std.debug.print("{s} ", .{item});
            }
        }
        std.debug.print("}} ", .{});
    }
    std.debug.print(" ]\n", .{});
}

// Process line in the form of "term1 : term2 term3 ..."
fn process_line(line: []const u8, comptime T: type, tsort: *TopoSort(T)) !void {
    var tokens      = std.mem.tokenizeScalar(u8, line, ':');
    const first     = tokens.next() orelse "";  // first token is the depending item.
    const dependent = std.mem.trim(u8, first, " \t\r\n");
    if (dependent.len == 0)
        return;
    const dep_num   = if (T == usize) try std.fmt.parseInt(usize, dependent, 10);

    const rest      = tokens.next() orelse "";  // the rest are leading/required items.
    var rest_tokens = std.mem.tokenizeScalar(u8, rest, ' ');
    while (rest_tokens.next()) |token| {
        const lead  = std.mem.trim(u8, token, " \t\r\n");
        if (T == usize) {
            const lead_num: ?T = if (lead.len == 0) null else try std.fmt.parseInt(usize, lead, 10);
            try tsort.add_dependency(lead_num, dep_num);
        } else {
            const lead_txt: ?T = if (lead.len == 0) null else lead;
            try tsort.add_dependency(lead_txt, dependent);
        }
    }
}


const CmdArgs = struct {
    arg_itr:        ArgIterator,
    program:        []const u8,
    data_file:      []const u8,
    is_int:         bool,

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

    fn parse(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .data_file = "data.txt",    // default to dependency file in the working dir.
            .is_int = false,
        };
        var argv = args.arg_itr;
        args.program = argv.next() orelse "";
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--data")) {
                args.data_file = std.mem.sliceTo(argv.next(), 0) orelse "data.txt";
            } else if (std.mem.eql(u8, arg, "--int")) {
                args.is_int = true;
            }
        }
        return args;
    }
};


