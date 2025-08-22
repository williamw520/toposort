// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();

const TopoSort = toposort.TopoSort;
const SortResult = toposort.SortResult;
const IntNode = usize;
const MyErrors = error{ MissingRangeValue, MissingGraphData };


/// A command line tool that reads dependency data from file and
/// does topological sort using the Toposort library.
/// This serves as an example to exercise the Toposort library API.
pub fn main() !void {
    {
        var args = try CmdArgs.init(g_allocator);
        defer args.deinit();
        args.parse() catch |err| {
            std.debug.print("Error in parsing command arguments. {}\n", .{err});
            usage(args);
            return;
        };

        const need_file_data = args.graph_data == null;
        var data: []const u8 = args.graph_data orelse undefined;

        if (need_file_data) {
            data = read_file(args.data_file) catch |err| {
                std.debug.print("Error in reading the data file. {}\n", .{err});
                usage(args);
                return;
            };
        }
        defer if (need_file_data) g_allocator.free(data);

        if (args.is_int) {
            const T = IntNode;
            try process_data(T, need_file_data, data, args);
        } else {
            const T = []const u8;
            try process_data(T, need_file_data, data, args);
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

fn process_data(comptime T: type, has_file_data: bool, data: []const u8, args: CmdArgs) !void {
    // This starts the steps of using TopoSort.
    var tsort = try TopoSort(T).init(g_allocator, .{
                                        .verbose = args.is_verbose,
                                        .max_range = args.max_range
                                    });
    defer tsort.deinit();

    if (has_file_data) {
        try add_file_data(data, T, &tsort);
    } else {
        try tsort.add_graph(data);
    }

    // Do the sort.
    const result = try tsort.sort();

    // Print the result.
    if (!result.has_cycle()) {
        std.debug.print("Processing succeeded.\n", .{});
        try dump_ordered(T, result);
        dump_nodes(T, result);
        dump_dep_tree(T, result);
    } else {
        std.debug.print("Failed to process graph data. Graph has cycles.\n", .{});
        try dump_ordered(T, result);
        dump_nodes(T, result);
        dump_cycle(T, result);
    }
}

fn add_file_data(data: []const u8, comptime T: type, tsort: *TopoSort(T)) !void {
    // Add the dependency of each line to TopoSort.
    var lines = std.mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        try process_line(line, T, tsort);
    }
}

// Process line in the form of "term1 : term2 term3 ..."
fn process_line(line: []const u8, comptime T: type, tsort: *TopoSort(T)) !void {
    var tokens      = std.mem.tokenizeScalar(u8, line, ':');
    const first     = tokens.next() orelse "";  // first token is the depending node.
    const dependent = std.mem.trim(u8, first, " \t\r\n");
    if (dependent.len == 0)
        return;

    const rest      = tokens.next() orelse "";  // the rest are leading/required nodes.
    var rest_tokens = std.mem.tokenizeScalar(u8, rest, ' ');
    while (rest_tokens.next()) |token| {
        const lead  = std.mem.trim(u8, token, " \t\r\n");
        if (T == IntNode) {
            const dep_num       = if (T == IntNode) try std.fmt.parseInt(IntNode, dependent, 10);
            const lead_num: ?T  = if (lead.len == 0) null else try std.fmt.parseInt(IntNode, lead, 10);
            try tsort.add(lead_num, dep_num);
        } else {
            const lead_txt: ?T  = if (lead.len == 0) null else lead;
            try tsort.add(lead_txt, dependent);
        }
    }
}

fn dump_ordered(comptime T: type, result: SortResult(T)) !void {
    std.debug.print("  Topologically sorted sets: [", .{});
    const sorted_sets: ArrayList(ArrayList(T)) = result.get_sorted_sets();
    for (sorted_sets.items) |set| {
        std.debug.print(" {{ ", .{});
        for (set.items) |node| dump_node(T, node);
        std.debug.print("}} ", .{});
    }
    std.debug.print(" ]\n", .{});

    std.debug.print("  Topologically sorted list: [ ", .{});
    var sorted_list = try result.get_sorted_list(g_allocator);
    defer sorted_list.deinit(g_allocator);
    for (sorted_list.items) |node| {
        dump_node(T, node);
    }
    std.debug.print("]\n", .{});
}

fn dump_nodes(comptime T: type, result: SortResult(T)) void {
    std.debug.print("  Nodes: [ ", .{});
    for (result.get_nodes().items) |node| dump_node(T, node);
    std.debug.print("]\n", .{});
}

fn dump_cycle(comptime T: type, result: SortResult(T)) void {
    std.debug.print("  Cycle: [ ", .{});
    for (result.get_cycle_set().items) |id| dump_node_by_id(T, result, id);
    std.debug.print("]\n", .{});
}

fn dump_dep_tree(comptime T: type, result: SortResult(T)) void {
    std.debug.print("  Dependency tree:\n", .{});
    dump_tree(T, result, null, result.get_root_set(), 2);
}

fn dump_tree(comptime T: type, result: SortResult(T), lead_id: ?u32,
             node_ids: ArrayList(u32), indent: usize) void {
    std.debug.print("{s: <[width]}", .{.value = "", .width = indent});
    if (lead_id) |id| {
        dump_node_by_id(T, result, id);
        std.debug.print("-> ", .{});
    }
    if (node_ids.items.len == 0) {
        std.debug.print("\n", .{});
        return;
    }
    std.debug.print("[ ", .{});
    for (node_ids.items) |node_id| {
        dump_node_by_id(T, result, node_id);
    }
    std.debug.print("]\n", .{});
    for (node_ids.items) |node_id| {
        dump_tree(T, result, node_id, result.get_dependents(node_id), indent + 2);
    }
}

fn dump_node_by_id(comptime T: type, result: SortResult(T), id: u32) void {
    dump_node(T, result.get_node(id));
}

fn dump_node(comptime T: type, node: T) void {
    if (T == IntNode) {
        std.debug.print("{} ", .{node});
    } else {
        std.debug.print("{s} ", .{node});
    }
}

fn usage(args: CmdArgs) void {
    const program_name = std.fs.path.basename(args.program);
    std.debug.print(
        \\
        \\Usage:
        \\  {s} --data data.file [--int] [--max-range N] [--verbose] [--graph data]
        \\
        \\      --data data.file  - contains the dependency node pairs. A: B, or A: B C D
        \\      --int  - treats the dependency node pair as numbers.
        \\      --max_range N  - gives max numeric range for the numeric node value.
        \\      --verbose  - prints processing messages.
        \\      --graph data  - where data is "(a b) (b c) (c d) ..."
        \\
        , .{program_name});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    const Self = @This();

    arg_itr:        ArgIterator,
    program:        []const u8,
    data_file:      []const u8,         // the dependency data file.
    graph_data:     ?[]const u8,        // the dependency data from command line.
    max_range:      ?usize,
    is_int:         bool,               // process the terms in file as number.
    is_verbose:     bool,

    fn init(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .data_file = "data.txt",    // default to data.txt in the working dir.
            .graph_data = null,
            .max_range = null,
            .is_int = false,
            .is_verbose = false,        // dump processing states.
        };
        var argv = args.arg_itr;
        args.program = argv.next() orelse "";
        return args;
    }

    fn parse(self: *Self) !void {
        var argv = self.arg_itr;
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--data")) {
                self.data_file = std.mem.sliceTo(argv.next(), 0) orelse "data.txt";
            } else if (std.mem.eql(u8, arg, "--int")) {
                self.is_int = true;
            } else if (std.mem.eql(u8, arg, "--max-range")) {
                if (std.mem.sliceTo(argv.next(), 0)) |range| {
                    self.max_range = try std.fmt.parseInt(usize, range, 10);
                    self.is_int = true; // setting the max numeric range is automatically an integer node.
                } else {
                    return error.MissingRangeValue;
                }
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                self.is_verbose = true;
            } else if (std.mem.eql(u8, arg, "--graph")) {
                if (std.mem.sliceTo(argv.next(), 0)) |data| {
                    self.graph_data = data;
                } else {
                    return error.MissingGraphData;
                }
            }
        }
    }

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

};


