
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const indexOfScalar = std.mem.indexOfScalar;


pub fn TopoSort(comptime T: type) type {
    return struct {
        const Self = @This();

        // Pub struct wraps a small number of fields to minimize copying cost.
        allocator:  Allocator,
        data:       *Data(T),

        pub fn init(allocator: Allocator, verbose: bool) !Self {
            const data_ptr = try allocator.create(Data(T));
            data_ptr.verbose = verbose;
            return .{
                .allocator = allocator,
                .data = try data_ptr.init_obj(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit_obj(self.allocator);
            self.allocator.destroy(self.data);
        }

        // The items are stored by value.  The memory for items are not duplicated.
        // For slice and pointer type items, memory is managed and retained by the caller.
        pub fn add_dependency(self: *Self, leading: ?T, dependent: T) !void {
            const dep_id    = try self.add_item(dependent);
            const lead_id   = if (leading) |lead| try self.add_item(lead) else null;
            const dep       = Dependency { .lead_id = lead_id, .dep_id = dep_id };
            try self.data.dependencies.append(dep);
            if (self.data.verbose) try self.dump_dependency(leading, dependent);
        }

        pub fn process(self: *Self) !bool {
            try self.setup_dependents();
            if (self.data.verbose) self.dump_dependents();
            try self.resolve();
            if (self.data.verbose) try self.dump_sorted();
            if (self.data.verbose) try self.dump_cycle();
            return !self.has_cycle();
        }

        pub fn get_sorted_sets(self: *Self) ArrayList(ArrayList(T)) {
            return self.data.sorted_sets;
        }

        pub fn get_root_set(self: *Self) ArrayList(T) {
            return self.data.root_set;
        }

        pub fn get_cycle(self: *Self) ArrayList(T) {
            return self.data.cycle;
        }

        pub fn get_items(self: *Self) ArrayList(T) {
            return self.data.unique_items;
        }

        // TODO: add get_dependents()

        fn resolve(self: *Self) !void {
            // counts of incoming leading links to each item.
            var incomings: []u32 = try self.allocator.alloc(u32, self.data.item_count());
            defer self.allocator.free(incomings);
            try self.setup_incomings(incomings);

            // track whether an item has been processed.
            var visited: []bool = try self.allocator.alloc(bool, self.data.item_count());
            defer self.allocator.free(visited);
            @memset(visited, false);

            // items that have no incoming leading links, i.e. they have no dependency.
            var curr_zeros = ArrayList(u32).init(self.allocator);
            var next_zeros = ArrayList(u32).init(self.allocator);
            defer curr_zeros.deinit();
            defer next_zeros.deinit();

            try scan_zero_incoming(incomings, &curr_zeros); // find the initial set.
            try self.add_root_set(curr_zeros);
            while (curr_zeros.items.len > 0) {
                try self.add_sorted_set(curr_zeros);        // emit items that depend on none.
                next_zeros.clearRetainingCapacity();        // reset array for the next round.
                for (curr_zeros.items) |zero_id| {
                    visited[zero_id] = true;
                    for (self.data.dependents[zero_id].items) |dep_id| {
                        if (visited[dep_id]) continue;
                        incomings[dep_id] -= 1;
                        if (incomings[dep_id] == 0) try next_zeros.append(dep_id);
                    }
                }
                std.mem.swap(ArrayList(u32), &curr_zeros, &next_zeros);
            }
            try self.collect_cycled_items(visited);

            if (self.data.verbose) try self.dump_incomings(incomings);
            if (self.data.verbose) try self.dump_visited(visited);
        }

        fn add_item(self: *Self, input_item: T) !u32 {
            if (self.get_id(input_item)) |item_id| {
                return item_id;
            } else {
                const new_id: u32 = @intCast(self.data.item_count());
                try self.data.unique_items.append(input_item);
                try self.data.item_map.put(input_item, new_id);
                return new_id;
            }
        }

        fn get_item(self: *Self, id: usize) T {
            return self.data.unique_items.items[id];
        }

        fn get_id(self: *Self, item: T) ?u32 {
            return self.data.item_map.get(item);
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

        fn scan_zero_incoming(incomings: []u32, found: *ArrayList(u32)) !void {
            for (incomings, 0..) |count, id| {
                if (count == 0) {
                    try found.append(@intCast(id));
                }
            }
        }

        fn add_root_set(self: *Self, root_zeros: ArrayList(u32)) !void {
            for (root_zeros.items) |id| {
                try self.data.root_set.append(self.get_item(id));
            }
        }

        fn add_sorted_set(self: *Self, curr_zeros: ArrayList(u32)) !void {
            var sorted_set = ArrayList(T).init(self.allocator);
            for (curr_zeros.items) |id| {
                try sorted_set.append(self.get_item(id));
            }
            try self.data.sorted_sets.append(sorted_set);
        }

        fn collect_cycled_items(self: *Self, visited: []bool) !void {
            for (visited, 0..) |flag, id| {
                if (!flag) {
                    try self.data.cycle.append(self.get_item(id));
                }
            }
        }

        fn has_cycle(self: *Self) bool {
            return self.data.cycle.items.len > 0;
        }

        fn dump_dependency(self: *Self, leading: ?T, dependent: T) !void {
            const depend_id     = self.get_id(dependent);
            const depend_txt    = try as_alloc_str(T, dependent, self.allocator);
            defer self.allocator.free(depend_txt);
            if (leading) |leading_data| {
                const lead_id   = self.get_id(leading_data);
                const lead_txt  = try as_alloc_str(T, leading_data, self.allocator);
                defer self.allocator.free(lead_txt);
                std.debug.print("  depend_id({any}:{s}) : lead_id({any}:{s})\n",
                                .{depend_id, depend_txt, lead_id, lead_txt});
            } else {
                std.debug.print("  depend_id({any}:{s}) : \n", .{depend_id, depend_txt});
            }
        }

        fn dump_dependents(self: *Self) void {
            std.debug.print("  dependents: [", .{});
            for (self.data.dependents) |list| {
                std.debug.print(" {any} ", .{list.items});
            }
            std.debug.print(" ]\n", .{});
        }

        fn dump_visited(self: *Self, visited: []bool) !void {
            std.debug.print("  visited: [ ", .{});
            for (visited, 0..) |flag, id| {
                const txt = try as_alloc_str(T, self.get_item(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} #{}, ", .{id, txt, flag});
            }
            std.debug.print("]\n", .{});
        }

        fn dump_incomings(self: *Self, incomings: []u32) !void {
            std.debug.print("  incomings: [ ", .{});
            for (incomings, 0..) |count, id| {
                const txt = try as_alloc_str(T, self.get_item(id), self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{}:{s} #{}, ", .{id, txt, count});
            }
            std.debug.print("]\n", .{});
        }

        fn dump_sorted(self: *Self) !void {
            std.debug.print("  sorted [", .{});
            for (self.data.sorted_sets.items) |sublist| {
                std.debug.print(" {{ ", .{});
                for(sublist.items) |item| {
                    if (self.get_id(item)) |id| {
                        const txt = try as_alloc_str(T, item, self.allocator);
                        defer self.allocator.free(txt);
                        std.debug.print("{}:{s} ", .{id, txt});
                    }
                }
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }

        fn dump_cycle(self: *Self) !void {
            std.debug.print("  cycle: [ ", .{});
            for (self.data.cycle.items) |item| {
                const id = self.get_id(item);
                const txt = try as_alloc_str(T, item, self.allocator);
                defer self.allocator.free(txt);
                std.debug.print("{any}:{s} ", .{id, txt});
            }
            std.debug.print("]\n", .{});
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
    
    const ItemMap = std.HashMap(T, u32,
                                ItemHashCtx(T),
                                std.hash_map.default_max_load_percentage);
    // const ItemMap = std.HashMap(T, u32,
    //                             if (HashCtx) HashCtx.? else ItemHashCtx(T),
    //                             std.hash_map.default_max_load_percentage);

    return struct {
        const Self = @This();

        unique_items:   ArrayList(T),               // the item list, without duplicates.
        item_map:       ItemMap,                    // maps item to sequential id.
        dependencies:   ArrayList(Dependency),      // the list of dependency pairs.
        dependents:     []ArrayList(u32),           // map item to its dependent ids. [[2, 3], [], [4]]
        sorted_sets:    ArrayList(ArrayList(T)),    // the T entry uses item memory from unique_items.
        root_set:       ArrayList(T),               // the root items that depend on none.
        cycle:          ArrayList(T),               // the item forming cycles.
        verbose:        bool = false,

        fn init_obj(self: *Self, allocator: Allocator) !*Self {
            self.dependencies = ArrayList(Dependency).init(allocator);
            self.item_map = ItemMap.init(allocator);
            self.unique_items = ArrayList(T).init(allocator);
            self.dependents = try allocator.alloc(ArrayList(u32), 0);
            self.sorted_sets = ArrayList(ArrayList(T)).init(allocator);
            self.root_set = ArrayList(T).init(allocator);
            self.cycle = ArrayList(T).init(allocator);
            return self;
        }

        fn deinit_obj(self: *Self, allocator: Allocator) void {
            self.cycle.deinit();
            self.root_set.deinit();
            self.free_sorted_sets();
            self.dependencies.deinit();
            self.free_dependents(allocator);
            self.item_map.deinit();
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
    };
}    

fn eql_value(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .Pointer) {
        return std.mem.eql(@typeInfo(T).Pointer.child, a, b);
    } else {
        return std.meta.eql(a, b);
    }
}

// The returned str must be freed with allocator.free().
fn as_alloc_str(comptime T: type, value: T, allocator: Allocator) ![]u8 {
    if (@typeInfo(T) == .Pointer) {
        return try std.fmt.allocPrint(allocator, "\"{s}\"", .{value});
    } else {
        return try std.fmt.allocPrint(allocator, "{any}", .{value});
    }
}

// Default hash context for the item type T.
fn ItemHashCtx(comptime T: type) type {
    return struct {
        pub fn hash(_: @This(), key: T) u64 {
            if (@typeInfo(T) == .Pointer) {
                // Note: this handles array of simple types.
                var h = std.hash.Wyhash.init(0);
                h.update(key);
                return h.final();
            } else {
                // Note: this handles simple types.
                var h = std.hash.Wyhash.init(0);
                h.update(std.mem.asBytes(&key));
                return h.final();
            }
        }

        pub fn eql(_: @This(), a: T, b: T) bool {
            return eql_value(T, a, b);
        }
    };
}


