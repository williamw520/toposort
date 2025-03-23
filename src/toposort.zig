
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;


pub fn TopoSort(comptime T: type) type {
    return struct {
        const Self = @This();

        // Pub struct wraps a small number of fields to minimize copying cost.
        allocator:  Allocator,
        data:       *Data(T),

        pub fn init(allocator: Allocator) !Self {
            const data_ptr = try allocator.create(Data(T));
            return .{
                .allocator = allocator,
                .data = try data_ptr.init_obj(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit_obj(self.allocator);
            self.allocator.destroy(self.data);
        }

        pub fn add_dependency(self: *Self, leading: T, dependent: T) !void {
            const dep_id    = try self.add_item(dependent);
            const lead_id   = try self.add_item(leading);
            try self.data.dependencies.append(Dependency { .lead_id = lead_id, .dep_id = dep_id });
            self.dump_dependency(leading, dependent);
        }

        pub fn process(self: *Self) !void {
            try self.add_dependents();
            try self.resolve();
            self.dump_dependents();
            self.dump_resolved();
        }

        fn resolve(self: *Self) !void {
            // counts of incoming leading links of each item.
            var incomings: []u32 = try self.allocator.alloc(u32, self.data.item_count());
            defer self.allocator.free(incomings);
            try self.add_incomings(incomings);
            
            // track whether an item has been processed.
            var visited: []bool = try self.allocator.alloc(bool, self.data.item_count());
            defer self.allocator.free(visited);
            @memset(visited, false);

            var curr_zeros = ArrayList(u32).init(self.allocator);
            defer curr_zeros.deinit();                      // free the last version of the list.

            try find_zero_incoming(incomings, &curr_zeros); // find the initial set.
            while (curr_zeros.items.len > 0) {
                try self.data.ordered_sets.append(curr_zeros);   // save the items depending on none.

                var next_zeros = ArrayList(u32).init(self.allocator);
                for (curr_zeros.items) |zero_id| {
                    visited[zero_id] = true;
                    const dependents_of_zero = &self.data.dependents[zero_id];
                    for (dependents_of_zero.items) |dep_id| {
                        if (visited[dep_id]) continue;
                        incomings[dep_id] -= 1;
                        if (incomings[dep_id] == 0) {
                            try next_zeros.append(dep_id);
                        }
                    }
                }
                curr_zeros = next_zeros;
            }
        }

        fn add_item(self: *Self, input_item: T) !u32 {
            if (self.data.item_map.get(input_item)) |item_id| {
                return item_id;
            } else {
                const new_id: u32 = @intCast(self.data.item_count());
                const dup_item: T = try dupe_value(T, input_item, self.allocator);
                try self.data.unique_items.append(dup_item);
                // use dup_item as key with its own memory as map stores the key.
                try self.data.item_map.put(dup_item, new_id);
                return new_id;
            }
        }

        fn add_dependents(self: *Self) !void {
            try self.data.realloc_dependents(self.allocator);  // re-alloc based on the current item count.
            for (self.data.dependencies.items) |dep| {
                var list_ptr = &self.data.dependents[dep.lead_id];
                const found = std.mem.indexOfScalar(u32, list_ptr.items, dep.dep_id);
                if (found == null) {
                    try list_ptr.append(dep.dep_id);
                }
            }
        }

        fn add_incomings(self: *Self, incomings: []u32) !void {
            @memset(incomings, 0);
            for (self.data.dependents) |list| {  // each item leads a list of dependents.
                for (list.items) |dep_id| { // all dep_id have one incoming from the leading item.
                    incomings[dep_id] += 1;    
                }
            }
        }

        fn find_zero_incoming(incomings: []u32, found: *ArrayList(u32)) !void {
            for (incomings, 0..) |count, id| {
                if (count == 0) {
                    try found.append(@intCast(id));
                }
            }
        }

        fn dump_dependency(self: *Self, leading: T, dependent: T) void {
            const lead_id   = self.data.item_map.get(leading);
            const depend_id = self.data.item_map.get(dependent);
            var buf1: [16]u8 = undefined;
            var buf2: [16]u8 = undefined;
            const txt1 = value_as_str(T, dependent, &buf1) catch "error as_str";
            const txt2 = value_as_str(T, leading, &buf2) catch "error as_str";
            std.debug.print("  depend_id({any}:{s}) : lead_id({any}:{s})\n", .{depend_id, txt1, lead_id, txt2});
        }

        fn dump_dependents(self: *Self) void {
            std.debug.print("  dependents: [", .{});
            for (self.data.dependents) |list| {
                std.debug.print(" {any} ", .{list.items});
            }
            std.debug.print(" ]\n", .{});
        }

        pub fn dump_resolved(self: *Self) void {
            std.debug.print("  topological sorted [", .{});
            for (self.data.ordered_sets.items) |sublist| {
                std.debug.print(" {{ ", .{});
                for(sublist.items) |id| {
                    var buf: [16]u8 = undefined;
                    const txt = value_as_str(T, self.data.unique_items.items[id], &buf) catch "error as_str";
                    std.debug.print("{}:{s} ", .{id, txt});
                }
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }        
    };

}


// Define a dependency between a leading item and a depending item.
const Dependency = struct {
    lead_id:    u32,
    dep_id:     u32,
};


// Internal struct holding all the dynamically allocated data.
fn Data(comptime T: type) type {
    const ItemMap = std.HashMap(T, u32, ItemHashCtx(T), std.hash_map.default_max_load_percentage);

    return struct {
        const Self = @This();

        dependencies:   ArrayList(Dependency),      // the list of dependency pairs.
        item_map:       ItemMap,
        unique_items:   ArrayList(T),               // the item list.
        dependents:     []ArrayList(u32),           // map each item to its dependent ids. [[2, 3], [], [4]]
        ordered_sets:   ArrayList(ArrayList(u32)),

        fn init_obj(self: *Self, allocator: Allocator) !*Self {
            self.dependencies = ArrayList(Dependency).init(allocator);
            self.item_map = ItemMap.init(allocator);
            self.unique_items = ArrayList(T).init(allocator);
            self.dependents = try allocator.alloc(ArrayList(u32), 0);
            self.ordered_sets = ArrayList(ArrayList(u32)).init(allocator);
            return self;
        }

        fn deinit_obj(self: *Self, allocator: Allocator) void {
            self.dependencies.deinit();
            self.item_map.deinit();
            self.free_unique_items(allocator);
            self.free_dependents(allocator);
            self.free_ordered_sets();
        }

        fn free_unique_items(self: *Self, allocator: Allocator) void {
            for (self.unique_items.items) |item| {
                free_value(T, item, allocator);
            }
            self.unique_items.deinit();
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

        fn free_ordered_sets(self: *Self) void {
            for (self.ordered_sets.items) |list| {
                list.deinit();
            }
            self.ordered_sets.deinit();
        }            

        fn item_count(self: *Self) usize {
            return self.unique_items.items.len;
        }
    };
}    

/// Clone a value of type T.  If it's a Pointer type (strings, slices), allocate memory for it.
/// Need to call free_value() on the duplicated value to free it.
fn dupe_value(comptime T: type, value: T, allocator: std.mem.Allocator) !T {
    if (@typeInfo(T) == .Pointer) {
        // Dynamically allocate memory for pointer type (e.g. strings, slices).
        return try allocator.dupe(@typeInfo(T).Pointer.child, value);
    } else {
        // Primitive values and structs with no heap allocation.
        return value;
    }
}

/// Free a value of type T whose memory was allocated before.
fn free_value(comptime T: type, value: T, allocator: std.mem.Allocator) void {
    if (@typeInfo(T) == .Pointer) {
        allocator.free(value);  // free the allocated memory for pointer type.
    }
}

fn eql_value(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .Pointer) {
        return std.mem.eql(@typeInfo(T).Pointer.child, a, b);
    } else {
        return a == b;
    }
}

fn value_as_str(comptime T: type, value: T, buf: []u8) ![]u8 {
    if (@typeInfo(T) == .Pointer) {
        return try std.fmt.bufPrint(buf, "\"{s}\"", .{value});
    } else {
        return try std.fmt.bufPrint(buf, "{any}", .{value});
    }
}

fn ItemHashCtx(comptime T: type) type {
    return struct {
        pub fn hash(_: @This(), key: T) u64 {
            var hashed: u64 = undefined;
            if (@typeInfo(T) == .Pointer) {
                var h = std.hash.Wyhash.init(0);
                h.update(key);
                hashed = h.final();
            } else {
                const num: u64 = @intCast(key);
                const bytes = @as([*]const u8, @ptrCast(&num))[0..@sizeOf(u64)];
                hashed = std.hash.Wyhash.hash(0, bytes);
            }
            return hashed;
        }

        pub fn eql(_: @This(), a: T, b: T) bool {
            return eql_value(T, a, b);
        }
    };
}

