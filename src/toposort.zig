
const std = @import("std");
const bitarray = @import("bitarray.zig");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const indexOfScalar = std.mem.indexOfScalar;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const BitArray = bitarray.BitArray;

pub fn TopoSort(comptime T: type) type {
    return struct {
        const Self = @This();

        // Pub struct wraps a small number of fields to minimize copying cost.
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
            self.data.deinit_obj(self.allocator);
            self.allocator.destroy(self.data);
        }

        // Items are stored by value.  The memory for items are not duplicated.
        // For slice and pointer type items, memory is managed and retained by the caller.
        pub fn add_dependency(self: *Self, leading: ?T, dependent: T) !void {
            const dep_id    = try self.data.add_item(dependent);
            const lead_id   = if (leading) |lead| try self.data.add_item(lead) else null;
            const dep       = Dependency { .lead_id = lead_id, .dep_id = dep_id };
            try self.data.dependencies.append(dep);
            if (self.data.verbose) try self.dump_dependency(leading, dependent);
        }

        // Perform the topological sort.
        pub fn sort(self: *Self) !SortResult(T) {
            // set up the item to dependents mapping, before setting up incomings.
            try self.setup_dependents();
            if (self.data.verbose) self.dump_dependents();

            // counts of incoming leading links to each item.
            const incomings: []u32 = try self.allocator.alloc(u32, self.data.item_count());
            defer self.allocator.free(incomings);
            try self.setup_incomings(incomings);

            // track whether an item has been resolveed.
            var visited = try BitArray.init(self.allocator, self.data.item_count());
            defer visited.deinit(self.allocator);

            if (self.data.verbose) {
                try self.dump_items();
                try self.dump_incomings(incomings);
                try self.dump_visited(visited);
            }

            try self.run_alogrithm(incomings, &visited);

            if (self.data.verbose) {
                try self.dump_incomings(incomings);
                try self.dump_visited(visited);
                try self.dump_sorted();
                try self.dump_cycle();
            }
            return SortResult(T).init(self.data);
        }

       fn run_alogrithm(self: *Self, incomings: []u32, visited: *BitArray) !void {
            // items that have no incoming leading links, i.e. they are not dependents.
            var curr_zeros = ArrayList(u32).init(self.allocator);
            var next_zeros = ArrayList(u32).init(self.allocator);
            defer curr_zeros.deinit();
            defer next_zeros.deinit();

            try scan_zero_incoming(incomings, &curr_zeros); // find the initial set.
            try self.add_root_set(curr_zeros);
            while (curr_zeros.items.len > 0) {
                try self.add_sorted_set(curr_zeros);        // emit non-dependent items.
                next_zeros.clearRetainingCapacity();        // reset array for the next round.
                for (curr_zeros.items) |zero_id| {
                    visited.on(zero_id);
                    for (self.data.dependents[zero_id].items) |dep_id| {
                        if (visited.get(dep_id)) continue;
                        incomings[dep_id] -= 1;
                        if (incomings[dep_id] == 0) try next_zeros.append(dep_id);
                    }
                }
                std.mem.swap(ArrayList(u32), &curr_zeros, &next_zeros);
            }
            try self.collect_cycled_items(visited);
        }

        fn setup_dependents(self: *Self) !void {
            // re-alloc the dependents array based on the current item count.
            try self.data.realloc_dependents(self.allocator);
            for (self.data.dependencies.items) |dep| {
                if (dep.lead_id) |lead_id| {
                    var leads_dependents = &self.data.dependents[lead_id];
                    if (null == indexOfScalar(u32, leads_dependents.items, dep.dep_id)) {
                        try leads_dependents.append(dep.dep_id);
                    }
                }
            }
        }

        fn setup_incomings(self: *Self, incomings: []u32) !void {
            @memset(incomings, 0);
            for (self.data.dependents) |list| { // each item leads a list of dependents.
                for (list.items) |dep_id| {     // all dep_id have one incoming from the leading item.
                    incomings[dep_id] += 1;
                }
            }
        }

        fn scan_zero_incoming(incomings: [] const u32, found: *ArrayList(u32)) !void {
            for (incomings, 0..) |count, id| {
                if (count == 0) {
                    try found.append(@intCast(id));
                }
            }
        }

        fn add_root_set(self: *Self, root_zeros: ArrayList(u32)) !void {
            self.data.root_set_id.clearRetainingCapacity();
            try self.data.root_set_id.appendSlice(root_zeros.items);
        }

        fn add_sorted_set(self: *Self, curr_zeros: ArrayList(u32)) !void {
            var sorted_set = ArrayList(T).init(self.allocator);
            for (curr_zeros.items) |id| {
                try sorted_set.append(self.data.get_item(id));
            }
            try self.data.sorted_sets.append(sorted_set);
        }

        fn collect_cycled_items(self: *Self, visited: *BitArray) !void {
            self.data.cycle.clearRetainingCapacity();
            for (0..visited.count) |id| {
                if (!visited.get(id)) {
                    try self.data.cycle.append(@intCast(id));
                }
            }
        }

        fn dump_dependency(self: Self, leading: ?T, dependent: T) !void {
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

        fn dump_dependents(self: Self) void {
            std.debug.print("  dependents: [", .{});
            for (self.data.dependents) |list| {
                std.debug.print(" {any} ", .{list.items});
            }
            std.debug.print(" ]\n", .{});
        }

        fn dump_items(self: Self) !void {
            std.debug.print("  items: [ ", .{});
            for (self.data.unique_items.items, 0..) |item, id| {
                const txt = try as_alloc_str(T, item, self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s}, ", .{id, txt});
            }
            std.debug.print("]\n", .{});
        }

        fn dump_visited(self: Self, visited: BitArray) !void {
            std.debug.print("  visited: [ ", .{});
            for (0..visited.count) |id| {
                const txt = try as_alloc_str(T, self.data.get_item(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} #{}, ", .{id, txt, visited.get(id)});
            }
            std.debug.print("]\n", .{});
        }

        fn dump_incomings(self: Self, incomings: []u32) !void {
            std.debug.print("  incomings: [ ", .{});
            for (incomings, 0..) |count, id| {
                const txt = try as_alloc_str(T, self.data.get_item(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} #{}, ", .{id, txt, count});
            }
            std.debug.print("]\n", .{});
        }

        fn dump_sorted(self: Self) !void {
            std.debug.print("  sorted [", .{});
            for (self.data.sorted_sets.items) |sublist| {
                std.debug.print(" {{ ", .{});
                for(sublist.items) |item| {
                    if (self.data.get_id(item)) |id| {
                        const txt = try as_alloc_str(T, item, self.allocator);
                        defer self.allocator.free(txt);
                        std.debug.print("{}:{s} ", .{id, txt});
                    }
                }
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }

        fn dump_cycle(self: Self) !void {
            std.debug.print("  cycle: [ ", .{});
            for (self.data.cycle.items) |id| {
                const item = self.data.get_item(id);
                const txt = try as_alloc_str(T, item, self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{any}:{s} ", .{id, txt});
            }
            std.debug.print("]\n", .{});
        }
        
    };

}


/// This is returned by TopoSort.resolve().  Cannot be created by itself.
/// This has the same lifetime as TopoSort.
pub fn SortResult(comptime T: type) type {
    return struct {
        const Self = @This();

        data:   *Data(T),

        fn init(data: *Data(T)) Self {
            return .{
                .data = data,
            };
        }

        pub fn get_sorted_sets(self: Self) ArrayList(ArrayList(T)) {
            return self.data.sorted_sets;
        }

        pub fn get_cycle(self: Self) ArrayList(u32) {
            return self.data.cycle;
        }

        pub fn has_cycle(self: Self) bool {
            return self.data.cycle.items.len > 0;
        }

        pub fn get_root_set_id(self: Self) ArrayList(u32) {
            return self.data.root_set_id;
        }

        pub fn item_count(self: Self) usize {
            return self.data.item_count();
        }

        pub fn get_items(self: Self) ArrayList(T) {
            return self.data.unique_items;
        }

        pub fn get_item(self: Self, id: usize) T {
            return self.data.get_item(id);
        }

        pub fn get_id(self: Self, item: T) ?u32 {
            return self.data.get_id(item);
        }

        pub fn get_dependents(self: Self, id: u32) ArrayList(u32) {
            return self.data.dependents[id];
        }

    };
}


// Define a dependency between a leading item and a depending item.
const Dependency = struct {
    lead_id:    ?u32,   // optional for depending item with no dependency.
    dep_id:     u32,    // the depending item
};


// Internal struct holding all the dynamically allocated data.
// Mainly dealing with allocation and deallocation.
fn Data(comptime T: type) type {

    // Treat slice "[]const u8" as string.
    const ItemMap = if (T == []const u8) StringHashMap(u32) else AutoHashMap(T, u32);

    return struct {
        const Self = @This();

        max_range:      ?usize,                     // preset max range of numeric items.
        unique_items:   ArrayList(T),               // the item list, without duplicates.
        item_map:       ItemMap,                    // maps item to sequential id.
        item_num_map:   []?u32,                     // maps numeric item directly to id.
        dependencies:   ArrayList(Dependency),      // the list of dependency pairs.
        dependents:     []ArrayList(u32),           // map item id to its dependent ids. [[2, 3], [], [4]]
        sorted_sets:    ArrayList(ArrayList(T)),    // item sets in order; items in each set are parallel.
        cycle:          ArrayList(u32),             // the item ids forming cycles.
        root_set_id:    ArrayList(u32),             // the root items that depend on none.
        verbose:        bool = false,

        fn init_obj(self: *Self, allocator: Allocator, max_range: ?usize, verbose: bool) !void {
            self.max_range = max_range;
            self.verbose = verbose;
            self.dependencies = ArrayList(Dependency).init(allocator);
            self.item_map = ItemMap.init(allocator);
            self.item_num_map = try allocator.alloc(?u32, max_range orelse 0);
            self.unique_items = ArrayList(T).init(allocator);
            self.dependents = try allocator.alloc(ArrayList(u32), 0);
            self.sorted_sets = ArrayList(ArrayList(T)).init(allocator);
            self.cycle = ArrayList(u32).init(allocator);
            self.root_set_id = ArrayList(u32).init(allocator);
            @memset(self.item_num_map, null);
        }

        fn deinit_obj(self: *Self, allocator: Allocator) void {
            self.cycle.deinit();
            self.root_set_id.deinit();
            self.free_sorted_sets();
            self.dependencies.deinit();
            self.free_dependents(allocator);
            self.item_map.deinit();
            allocator.free(self.item_num_map);
            self.unique_items.deinit();
        }

        fn free_sorted_sets(self: *Self) void {
            for (self.sorted_sets.items) |list| {
                list.deinit();
            }
            self.sorted_sets.deinit();
        }            

        fn free_dependents(self: *Self, allocator: Allocator) void {
            for (self.dependents) |item_list| {
                item_list.deinit();
            }
            allocator.free(self.dependents);
        }

        fn realloc_dependents(self: *Self, allocator: Allocator) !void {
            self.free_dependents(allocator);
            self.dependents = try allocator.alloc(ArrayList(u32), self.item_count());
            for (0..self.dependents.len) |i| {
                self.dependents[i] = ArrayList(u32).init(allocator);
            }
        }

        fn item_count(self: *Self) usize {
            return self.unique_items.items.len;
        }

        fn get_item(self: *Self, id: usize) T {
            return self.unique_items.items[id];
        }

        fn get_id(self: *Self, item: T) ?u32 {
            // Mapping an item to its id depends on whether the item type is simple integer
            // and max_range for the numeric item has been set.
            if (@typeInfo(T) == .int and self.max_range != null) {
                // Direct mapping using a numeric array is faster than using a hashmap.
                return self.item_num_map[@intCast(item)];
            } else {
                // For complex item type, mapping requires a hashmap.
                return self.item_map.get(item);
            }
        }

        fn add_item(self: *Self, input_item: T) !u32 {
            if (self.get_id(input_item)) |item_id| {
                return item_id;
            } else {
                const new_id: u32 = @intCast(self.item_count());
                try self.unique_items.append(input_item);
                if (@typeInfo(T) == .int and self.max_range != null) {
                    self.item_num_map[@intCast(input_item)] = new_id;
                } else {
                    try self.item_map.put(input_item, new_id);
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

    try tests.benchmark1();
    try tests.benchmark2();
    try tests.benchmark3();
    try tests.benchmark4();
    
}

