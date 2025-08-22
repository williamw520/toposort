// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const indexOfScalar = std.mem.indexOfScalar;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const parseInt = std.fmt.parseInt;
const tokenizeScalar = std.mem.tokenizeScalar;


pub fn TopoSort(comptime T: type) type {
    return struct {
        const Self = @This();

        // Public struct wraps a small number of fields to minimize copying cost.
        allocator:  Allocator,
        data:       *Data(T),   // copies of TopoSort have the same Data pointer.

        pub fn init(allocator: Allocator,
                    options: struct {
                        max_range: ?usize = null,
                        verbose: bool = false,
                    } ) !Self {
            const data = try allocator.create(Data(T));
            try data.init_obj(allocator, options.max_range, options.verbose);
            return .{ .allocator = allocator, .data = data };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit_obj();
            self.allocator.destroy(self.data);
        }

        /// Add the leading node and the dependent node pair.
        /// Nodes are stored by value. For slice and pointer type nodes,
        /// the memory for nodes are not duplicated. Memory is managed by caller.
        pub fn add(self: *Self, leading: ?T, dependent: T) !void {
            const dep_id    = try self.data.add_node(dependent);
            const lead_id   = if (leading) |lead| try self.data.add_node(lead) else null;
            const dep_pair  = Dependency { .lead_id = lead_id, .dep_id = dep_id };
            try self.data.dependencies.append(self.allocator, dep_pair);
            if (self.data.verbose) try self.print_dependency(leading, dependent);
        }

        /// Add a dependency where the dependent node depends on the leading node,
        /// similar to the makefile rule - A: B.
        pub fn add_dep(self: *Self, dependent: T, leading: ?T) !void {
            try self.add(leading, dependent);
        }

        /// Add dependencies where the dependent node depends on a number of leading nodes,
        /// similar to the makefile rule - A: B C D
        pub fn add_deps(self: *Self, dependent: T, leadings: []const T) !void {
            for (leadings) |leading| {
                try self.add(leading, dependent);
            }
        }

        /// Add graph data from text input, in the form of:
        /// "(a b) (a c) (d) (c e f g)"
        /// where a depends on b, a on c, d on none, and c on e/f/g.
        pub fn add_graph(self: *Self, graph_data: []const u8) !void {
            var rules = tokenizeScalar(u8, graph_data, '(');        // break by '('
            while (rules.next()) |each_rule| {
                const rule = std.mem.trim(u8, each_rule, " )");     // trim off ' ' and ')'
                var terms = tokenizeScalar(u8, rule, ' ');          // break by ' '
                const dep = terms.next() orelse "";
                if (dep.len > 0 and terms.peek() == null) {
                    const d = if (@typeInfo(T) == .int) try parseInt(T, dep, 10) else dep;
                    try self.add(null, d);
                }
                while (terms.next()) |lead| {
                    if (@typeInfo(T) == .int) {
                        try self.add(try parseInt(T, lead, 10), try parseInt(T, dep, 10));
                    } else {
                        try self.add(lead, dep);
                    }
                }
            }
        }

        /// Perform the topological sort.
        pub fn sort(self: *Self) !SortResult(T) {
            // set up the leads to dependents mapping, before setting up incomings.
            try self.setup_leaders_dependents();
            if (self.data.verbose) self.print_dependents();
            if (self.data.verbose) self.print_leaders();

            // count the incoming leading links to each node.
            const incomings: []u32 = try self.allocator.alloc(u32, self.data.node_count());
            defer self.allocator.free(incomings);
            try self.setup_incomings(incomings);

            // track whether a node has been rooted, for finding cycles.
            const rooted: []bool = try self.allocator.alloc(bool, self.data.node_count());
            defer self.allocator.free(rooted);
            @memset(rooted, false);
            
            if (self.data.verbose) {
                try self.print_nodes();
                try self.print_incomings(incomings);    // print the before counts.
            }

            try self.run_algorithm(incomings, rooted);

            if (self.data.verbose) {
                try self.print_incomings(incomings);    // print the after counts.
                try self.print_rooted(rooted);
                try self.print_sorted();
                try self.print_cycle();
            }

            return SortResult(T).init(self.data);
        }

        // This is a variant to the Kahn's algorithm, with the additions on
        // finding dependence-free subsets and finding the cyclic nodes.
        //
        // This algorithm iteratively finds out the root sets of the graph.
        // 1. Find the first root set of the graph.
        // 2. Remove the nodes of the root set from the graph.
        // 3. Find the next root set. Go to 2 until the graph is empty.
        // The successive root sets form a topological order.
        // A root set consists of nodes depending on no other nodes, i.e.
        // nodes whose incoming link count is 0.
        fn run_algorithm(self: *Self, incomings: []u32, rooted: []bool) !void {
            // Double-buffer to hold the root sets of the graph for each round.
            // Root nodes have no incoming leading links, i.e. they depend on no one.
            var curr_root: ArrayList(u32) = .empty;
            var next_root: ArrayList(u32) = .empty;
            defer curr_root.deinit(self.allocator);
            defer next_root.deinit(self.allocator);

            try self.scan_zero_incoming(incomings, &curr_root); // find the initial root set.
            try self.save_root_set(curr_root);              // the real root set of the graph.
            while (curr_root.items.len > 0) {
                try self.emit_sorted_set(curr_root);        // emit the non-dependent set.
                for (curr_root.items) |root_id| rooted[root_id] = true;
                for (curr_root.items) |root_id| {
                    // decrement the incomings of the root's dependents to remove the root.
                    for (self.data.dependents[root_id].items) |dep_id| {
                        if (rooted[dep_id])                 // dependent was a root node already.
                            continue;                       // cycle detected; skip.
                        incomings[dep_id] -= 1;
                        if (incomings[dep_id] == 0) try next_root.append(self.allocator, dep_id);
                    }
                }
                std.mem.swap(ArrayList(u32), &curr_root, &next_root);
                next_root.clearRetainingCapacity();         // reset for next round.
            }
            try self.collect_cyclic_nodes(rooted);
        }

        fn setup_leaders_dependents(self: *Self) !void {
            // re-alloc the arrays based on the current node count.
            try self.data.realloc_dependents(self.allocator);
            try self.data.realloc_leaders(self.allocator);
            for (self.data.dependencies.items) |dep| {
                if (dep.lead_id) |lead_id| {
                    var leads_dependents = &self.data.dependents[lead_id];
                    if (null == indexOfScalar(u32, leads_dependents.items, dep.dep_id)) {
                        try leads_dependents.append(self.allocator, dep.dep_id);
                    }
                    var deps_leaders = &self.data.leaders[dep.dep_id];
                    if (null == indexOfScalar(u32, deps_leaders.items, lead_id)) {
                        try deps_leaders.append(self.allocator, lead_id);
                    }
                }
            }
        }

        fn setup_incomings(self: *Self, incomings: []u32) !void {
            @memset(incomings, 0);
            for (self.data.dependents) |deps| { // each node leads a list of dependents.
                for (deps.items) |dep_id| {
                    incomings[dep_id] += 1;     // each dep_id has one incoming from the leading node.
                }
            }
        }

        fn scan_zero_incoming(self: *Self, incomings: [] const u32, found: *ArrayList(u32)) !void {
            for (incomings, 0..) |count, id| {
                if (count == 0) try found.append(self.allocator, @intCast(id));
            }
        }

        // Save the root set to the entire graph.
        fn save_root_set(self: *Self, root_set: ArrayList(u32)) !void {
            self.data.root_set_id.clearRetainingCapacity();
            try self.data.root_set_id.appendSlice(self.allocator, root_set.items);
        }

        // Save the root set in the topological order result.
        fn emit_sorted_set(self: *Self, curr_root: ArrayList(u32)) !void {
            var sorted_set: ArrayList(T) = .empty;
            for (curr_root.items) |id| {
                try sorted_set.append(self.allocator, self.data.get_node(id));
            }
            try self.data.sorted_sets.append(self.allocator, sorted_set);
        }

        fn collect_cyclic_nodes(self: *Self, rooted: []bool) !void {
            self.data.cycle.clearRetainingCapacity();
            for (rooted, 0..) |flag, id| {
                // Node not rooted was skipped in run_algorithm() due to cycle detected.
                if (!flag) try self.data.cycle.append(self.allocator, @intCast(id));
            }
        }

        fn print_dependency(self: Self, leading: ?T, dependent: T) !void {
            const depend_id     = self.data.get_id(dependent);
            const depend_txt    = try as_alloc_str(T, dependent, self.allocator);
            defer self.allocator.free(depend_txt);
            if (leading) |leading_data| {
                const lead_id   = self.data.get_id(leading_data);
                const lead_txt  = try as_alloc_str(T, leading_data, self.allocator);
                defer self.allocator.free(lead_txt);
                std.debug.print("  depend_id({any}:{s}) : lead_id({any}:{s})\n",
                                .{depend_id, depend_txt, lead_id, lead_txt});
            } else {
                std.debug.print("  depend_id({any}:{s}) : \n", .{depend_id, depend_txt});
            }
        }

        fn print_dependents(self: Self) void {
            std.debug.print("  dependents: [", .{});
            for (self.data.dependents) |list| std.debug.print(" {any} ", .{list.items});
            std.debug.print(" ]\n", .{});
        }

        fn print_leaders(self: Self) void {
            std.debug.print("  leaders: [", .{});
            for (self.data.leaders) |list| std.debug.print(" {any} ", .{list.items});
            std.debug.print(" ]\n", .{});
        }

        fn print_nodes(self: Self) !void {
            std.debug.print("  nodes: [ ", .{});
            for (self.data.unique_nodes.items, 0..) |node, id| {
                const txt = try as_alloc_str(T, node, self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s}, ", .{id, txt});
            }
            std.debug.print("]\n", .{});
        }

        fn print_rooted(self: Self, rooted: []bool) !void {
            std.debug.print("  rooted: [ ", .{});
            for (rooted, 0..) |flag, id| {
                const txt = try as_alloc_str(T, self.data.get_node(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} {}, ", .{id, txt, flag});
            }
            std.debug.print("]\n", .{});
        }

        fn print_incomings(self: Self, incomings: []u32) !void {
            std.debug.print("  incomings: [ ", .{});
            for (incomings, 0..) |count, id| {
                const txt = try as_alloc_str(T, self.data.get_node(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} n={}, ", .{id, txt, count});
            }
            std.debug.print("]\n", .{});
        }

        fn print_sorted(self: Self) !void {
            std.debug.print("  sorted sets [", .{});
            for (self.data.sorted_sets.items) |sublist| {
                std.debug.print(" {{ ", .{});
                for(sublist.items) |node| {
                    if (self.data.get_id(node)) |id| {
                        const txt = try as_alloc_str(T, node, self.allocator);
                        defer self.allocator.free(txt);
                        std.debug.print("{}:{s} ", .{id, txt});
                    }
                }
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }

        fn print_cycle(self: Self) !void {
            std.debug.print("  cycle: [ ", .{});
            for (self.data.cycle.items) |id| {
                const node = self.data.get_node(id);
                const txt = try as_alloc_str(T, node, self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{any}:{s} ", .{id, txt});
            }
            std.debug.print("]\n", .{});
        }
        
    };

}


/// This is the result returned by TopoSort.sort().  Cannot be created by itself.
/// This has the same lifetime as TopoSort.
pub fn SortResult(comptime T: type) type {
    return struct {
        const Self = @This();

        data:   *Data(T),

        fn init(data: *Data(T)) Self {
            return .{ .data = data };
        }

        /// Return the topologically sorted sets of nodes.
        pub fn get_sorted_sets(self: Self) ArrayList(ArrayList(T)) {
            return self.data.sorted_sets;
        }

        /// Copy the topologically sorted nodes into the ArrayList provided by caller.
        /// Return the caller provided list.
        pub fn get_sorted_list(self: Self, allocator: Allocator) !ArrayList(T) {
            var sorted_list: ArrayList(T) = .empty;
            for (self.get_sorted_sets().items) |set| {
                for (set.items) |node| try sorted_list.append(allocator, node);
            }
            return sorted_list;
        }

        /// Report whether the graph has cycle(s).
        pub fn has_cycle(self: Self) bool {
            return self.data.cycle.items.len > 0;
        }

        /// Return the set of cyclic node id.  Use get_node() to get node value from id.
        pub fn get_cycle_set(self: Self) ArrayList(u32) {
            return self.data.cycle;
        }

        /// Return the set of root node id that depend on no other nodes.
        /// These are the root nodes to traverse the whole graph.
        /// Use get_node() to get node value from id.
        pub fn get_root_set(self: Self) ArrayList(u32) {
            return self.data.root_set_id;
        }

        /// Return the count of nodes in the graph.
        pub fn node_count(self: Self) usize {
            return self.data.node_count();
        }

        /// Return the list of nodes in the graph.
        pub fn get_nodes(self: Self) ArrayList(T) {
            return self.data.unique_nodes;
        }

        /// Get the node by the id, where id is an internally generated id.
        pub fn get_node(self: Self, id: usize) T {
            return self.data.get_node(id);
        }

        /// Get the id by the node, where id is an internally generated id.
        pub fn get_id(self: Self, node: T) ?u32 {
            return self.data.get_id(node);
        }

        /// Get the list of dependent node id of the leading node id.
        pub fn get_dependents(self: Self, leading_id: u32) ArrayList(u32) {
            return self.data.dependents[leading_id];
        }

        /// Get the list of leading node id of the dependent node id.
        pub fn get_leaders(self: Self, dependent_id: u32) ArrayList(u32) {
            return self.data.leaders[dependent_id];
        }

    };
}


// Define a dependency between a leading node and a depending node.
const Dependency = struct {
    lead_id:    ?u32,   // optional for a node that depends on no one.
    dep_id:     u32,    // the depending node
};


// Internal struct holding all the dynamically allocated data.
// Mainly dealing with allocation and deallocation.
fn Data(comptime T: type) type {

    // Treat slice "[]const u8" as string.
    const NodeMap = if (T == []const u8) StringHashMap(u32) else AutoHashMap(T, u32);

    return struct {
        const Self = @This();

        allocator:      Allocator,
        max_range:      ?usize,                     // preset max range of numeric nodes.
        unique_nodes:   ArrayList(T),               // the node list, without duplicates.
        node_map:       NodeMap,                    // maps node to sequential id.
        node_num_map:   []?u32,                     // maps numeric node directly to id.
        dependencies:   ArrayList(Dependency),      // the list of dependency pairs.
        dependents:     []ArrayList(u32),           // map node id to its dependent ids. [[1, 2], [], [1]]
        leaders:        []ArrayList(u32),           // map node id to its leader ids. [[], [0, 2], [0]]
        sorted_sets:    ArrayList(ArrayList(T)),    // node sets in order; nodes in each set are parallel.
        cycle:          ArrayList(u32),             // the node ids forming cycles.
        root_set_id:    ArrayList(u32),             // the root node ids that depend on no one.
        verbose:        bool = false,

        fn init_obj(self: *Self, allocator: Allocator, max_range: ?usize, verbose: bool) !void {
            self.allocator = allocator;
            self.max_range = max_range;
            self.verbose = verbose;
            self.dependencies = .empty;
            self.node_map = NodeMap.init(allocator);
            self.node_num_map = try allocator.alloc(?u32, if (max_range)|n| n+1 else 0);
            self.unique_nodes = .empty;
            self.dependents = try allocator.alloc(ArrayList(u32), 0);
            self.leaders = try allocator.alloc(ArrayList(u32), 0);
            self.sorted_sets = .empty;
            self.cycle = .empty;
            self.root_set_id = .empty;
            @memset(self.node_num_map, null);
        }

        fn deinit_obj(self: *Self) void {
            self.cycle.deinit(self.allocator);
            self.root_set_id.deinit(self.allocator);
            self.free_sorted_sets();
            self.dependencies.deinit(self.allocator);
            self.free_dependents();
            self.free_leaders(self.allocator);
            self.node_map.deinit();
            self.allocator.free(self.node_num_map);
            self.unique_nodes.deinit(self.allocator);
        }

        fn free_sorted_sets(self: *Self) void {
            for (self.sorted_sets.items) |*list| list.deinit(self.allocator);
            self.sorted_sets.deinit(self.allocator);
        }            

        fn free_dependents(self: *Self) void {
            for (self.dependents) |*dep_list| dep_list.deinit(self.allocator);
            self.allocator.free(self.dependents);
        }

        fn free_leaders(self: *Self, allocator: Allocator) void {
            for (self.leaders) |*lead_list| lead_list.deinit(self.allocator);
            allocator.free(self.leaders);
        }

        fn realloc_dependents(self: *Self, allocator: Allocator) !void {
            self.free_dependents();
            self.dependents = try allocator.alloc(ArrayList(u32), self.node_count());
            for (0..self.dependents.len) |i| {
                self.dependents[i] = .empty;
            }
        }

        fn realloc_leaders(self: *Self, allocator: Allocator) !void {
            self.free_leaders(allocator);
            self.leaders = try allocator.alloc(ArrayList(u32), self.node_count());
            for (0..self.leaders.len) |i| {
                self.leaders[i] = .empty;
            }
        }

        fn node_count(self: *Self) usize {
            return self.unique_nodes.items.len;
        }

        fn get_node(self: *Self, id: usize) T {
            return self.unique_nodes.items[id];
        }

        fn get_id(self: *Self, node: T) ?u32 {
            // Mapping a node to its id depends on whether the node type is simple integer type.
            // and max_range for the numeric node has been set.
            if (@typeInfo(T) == .int and self.max_range != null) {
                // Direct mapping using a numeric array is faster than using a hashmap.
                return self.node_num_map[@intCast(node)];
            } else {
                // For complex node type, mapping requires a hashmap.
                return self.node_map.get(node);
            }
        }

        fn add_node(self: *Self, input_node: T) !u32 {
            if (self.get_id(input_node)) |node_id| {
                return node_id;
            } else {
                const new_id: u32 = @intCast(self.node_count());
                try self.unique_nodes.append(self.allocator, input_node);
                if (@typeInfo(T) == .int and self.max_range != null) {
                    self.node_num_map[@intCast(input_node)] = new_id;
                } else {
                    try self.node_map.put(input_node, new_id);
                }
                return new_id;
            }
        }

    };
}    

// The returned str must be freed with allocator.free().
fn as_alloc_str(comptime T: type, value: T, allocator: Allocator) ![]u8 {
    if (@typeInfo(T) == Type.pointer) {
        return try std.fmt.allocPrint(allocator, "\"{s}\"", .{value});
    } else {
        return try std.fmt.allocPrint(allocator, "{any}", .{value});
    }
}


test {
    const tests = @import("tests.zig");

    // Repeat 6 times and throw away the slowest.

    std.debug.print("\nBenchmark increasing node in 10X scale on branching 1, no max_range\n", .{});
    try tests.benchmark(10000, 1, false, 6, .{ .add = true, .sort = true, .total = false });
    try tests.benchmark(100000, 1, false, 6, .{ .add = true, .sort = true, .total = false });
    try tests.benchmark(1000000, 1, false, 6, .{ .add = true, .sort = true, .total = false });

    std.debug.print("\nBenchmark increasing node in 10X scale on branching 1, with max_range\n", .{});
    try tests.benchmark(10000, 1, true, 6, .{ .add = true, .sort = true, .total = false });
    try tests.benchmark(100000, 1, true, 6, .{ .add = true, .sort = true, .total = false });
    try tests.benchmark(1000000, 1, true, 6, .{ .add = true, .sort = true, .total = false });

    std.debug.print("\nBenchmark increasing nodes on fixed branching, with max_range\n", .{});
    try tests.benchmark(10000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(20000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(30000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(40000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(50000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(100000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(200000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(300000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(400000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(500000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(600000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(700000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(800000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(900000, 1000, true, 6, .{ .total = true });
    try tests.benchmark(1000000, 1000, true, 6, .{ .total = true });

    std.debug.print("\nBenchmark increasing node and increasing link branching, with max_range\n", .{});
    try tests.benchmark(10000, 2, true, 6, .{ .total = true });
    try tests.benchmark(100000, 2, true, 6, .{ .total = true });
    try tests.benchmark(1000000, 2, true, 6, .{ .total = true });

    try tests.benchmark(10000, 10, true, 6, .{});
    try tests.benchmark(100000, 10, true, 6, .{});
    try tests.benchmark(1000000, 10, true, 6, .{});

    try tests.benchmark(10000, 100, true, 6, .{});
    try tests.benchmark(100000, 100, true, 6, .{});
    try tests.benchmark(1000000, 100, true, 6, .{});

    try tests.benchmark(10000, 1000, true, 6, .{});
    try tests.benchmark(100000, 1000, true, 6, .{});
    try tests.benchmark(1000000, 1000, true, 6, .{});

    try tests.benchmark(10000, 2000, true, 6, .{});
    try tests.benchmark(100000, 2000, true, 6, .{});
    try tests.benchmark(1000000, 2000, true, 6, .{});

    try tests.benchmark(10000, 3000, true, 6, .{});
    try tests.benchmark(100000, 3000, true, 6, .{});
    try tests.benchmark(1000000, 3000, true, 6, .{});

    try tests.benchmark(10000, 4000, true, 6, .{});
    try tests.benchmark(100000, 4000, true, 6, .{});
    try tests.benchmark(1000000, 4000, true, 6, .{});

    try tests.benchmark(10000, 5000, true, 6, .{});
    try tests.benchmark(100000, 5000, true, 6, .{});
    try tests.benchmark(1000000, 5000, true, 6, .{});

    // std.debug.print("\nBenchmark increasing node and increasing link branching, with max_range\n", .{});
    // for (1..5)|links| {
    //     for (1..11)|nodes| {
    //         try tests.benchmark(100000*nodes, 1000*links, true, 3, .{});
    //     }
    // }

    // std.debug.print("\nBenchmark increasing large link branching, with max_range\n", .{});
    // try tests.benchmark(1000000, 100, true, 3, .{});
    // try tests.benchmark(1000000, 200, true, 3, .{});
    // try tests.benchmark(1000000, 300, true, 3, .{});
    // try tests.benchmark(1000000, 400, true, 3, .{});
    // try tests.benchmark(1000000, 500, true, 3, .{});
    // try tests.benchmark(1000000, 600, true, 3, .{});
    
    // try tests.benchmark(1000000, 1000, true, 3, .{});
    // try tests.benchmark(1000000, 2000, true, 3, .{});
    // try tests.benchmark(1000000, 3000, true, 3, .{});
    // try tests.benchmark(1000000, 4000, true, 3, .{});
    // try tests.benchmark(1000000, 5000, true, 3, .{});
    // try tests.benchmark(1000000, 6000, true, 3, .{});
    
    // try tests.benchmark(1000000, 10000, true, 3, .{});
    // try tests.benchmark(1000000, 20000, true, 3, .{});
    // try tests.benchmark(1000000, 30000, true, 3, .{});
    // try tests.benchmark(1000000, 40000, true, 3, .{});
    // try tests.benchmark(1000000, 50000, true, 3, .{});
    // try tests.benchmark(1000000, 60000, true, 3, .{});
    
    // try tests.benchmark(1000000, 100000, true, 3, .{});
    // try tests.benchmark(1000000, 200000, true, 3, .{});
    // try tests.benchmark(1000000, 300000, true, 3, .{});
    // try tests.benchmark(1000000, 400000, true, 3, .{});
    // try tests.benchmark(1000000, 500000, true, 3, .{});
    
}

