
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;


pub fn TopoSort(comptime T: type) type {

    const ItemMap = std.HashMap(T, u32, ItemHashCtx(T), std.hash_map.default_max_load_percentage);

    return struct {
        const Self = @This();
        allocator:      Allocator,
        dependencies:   ArrayList(Dependency(T)),   // the list of dependency pairs.
        unique_items:   ArrayList(T),               // the list of unique items.
        item_map:       ItemMap,                    // map item (as key) to item id.
        dependents:     []ArrayList(u32),           // map each item to its dependent ids. [[2, 3], [], [4]]
        incomings:      []u32,                      // counts of incoming leading links of each item.
        visited:        []bool,                     // track whether an item has been processed.
        ordered_sets:   ArrayList(ArrayList(u32)),

        pub fn init(allocator: Allocator) !*Self {
            const obj_ptr = try allocator.create(Self);
            obj_ptr.* = Self {
                .allocator = allocator,
                .dependencies = ArrayList(Dependency(T)).init(allocator),
                .item_map = ItemMap.init(allocator),
                .unique_items = ArrayList(T).init(allocator),
                .dependents = undefined,
                .incomings = undefined,
                .visited = undefined,
                .ordered_sets = ArrayList(ArrayList(u32)).init(allocator),
            };
            return obj_ptr;
        }

        pub fn deinit(self: *Self) void {
            for (self.dependencies.items) |*dep| {
                dep.deinit(self.allocator);
            }
            self.dependencies.deinit();
            self.item_map.deinit();

            for (self.unique_items.items) |item| {
                free_value(T, item, self.allocator);
            }
            self.unique_items.deinit();

            for (self.dependents) |dep_list| {
                dep_list.deinit();
            }
            self.allocator.free(self.dependents);
            self.allocator.free(self.incomings);
            self.allocator.free(self.visited);

            for (self.ordered_sets.items) |list| {
                list.deinit();
            }
            self.ordered_sets.deinit();

            // TODO: do it right.
            self.allocator.destroy(self);
        }

        fn item_count(self: *Self) usize {
            return self.unique_items.items.len;
        }

        pub fn add_dependency(self: *Self, leading: T, dependent: T) !void {
            var buf1: [16]u8 = undefined;
            var buf2: [16]u8 = undefined;
            const leading_txt   = try value_as_str(T, leading, &buf1);
            const dependent_txt = try value_as_str(T, dependent, &buf2);
            std.debug.print("add(), leading: {s} => dependent: {s}\n", .{leading_txt, dependent_txt});
            const dep = try Dependency(T).init(self.allocator, leading, dependent);
            try self.dependencies.append(dep);
        }

        pub fn process(self: *Self) !void {
            try self.setup();

            var curr_found = ArrayList(u32).init(self.allocator);
            try self.scan_incoming_counts(&curr_found);

            while (curr_found.items.len > 0) {
                var next_found = ArrayList(u32).init(self.allocator);
                try self.ordered_sets.append(curr_found);
                for (curr_found.items) |found_id| {
                    self.visited[found_id] = true;
                    const deps_of_found = &self.dependents[found_id];
                    for (deps_of_found.items) |dep_id| {
                        if (self.visited[dep_id] == false) {
                            self.incomings[dep_id] -= 1;
                            if (self.incomings[dep_id] == 0) {
                                try next_found.append(dep_id);
                            }
                        }
                    }
                }
                curr_found = next_found;
            }
            curr_found.deinit();

            std.debug.print("  ordered [", .{});
            for (self.ordered_sets.items) |sublist| {
                std.debug.print(" {{ ", .{});
                for(sublist.items) |id| {
                    var buf: [16]u8 = undefined;
                    const txt = value_as_str(T, self.unique_items.items[id], &buf) catch "error as_str";
                    std.debug.print("{}:{s} ", .{id, txt});
                }
                std.debug.print("}} ", .{});
            }
            std.debug.print(" ]\n", .{});
        }

        fn setup(self: *Self) !void {
            for (self.dependencies.items) |dep| {
                const dep_id    = try self.add_item(dep.dependent);
                const lead_id   = try self.add_item(dep.leading);
                var buf1: [16]u8 = undefined;
                var buf2: [16]u8 = undefined;
                const txt1 = value_as_str(T, dep.dependent, &buf1) catch "error as_str";
                const txt2 = value_as_str(T, dep.leading, &buf2) catch "error as_str";
                std.debug.print("  dep_id({}:{s}) : lead_id({}:{s})\n", .{dep_id, txt1, lead_id, txt2});
            }
            try self.alloc_arrays();
            try self.add_dependents();
            try self.add_incomings();
        }

        fn scan_incoming_counts(self: *Self, found: *ArrayList(u32)) !void {
            for (self.incomings, 0..) |count, id| {
                if (count == 0) {
                    try found.append(@intCast(id));
                }
            }
        }

        fn add_item(self: *Self, ts_item: T) !u32 {
            var buf: [16]u8 = undefined;
            const item_txt = value_as_str(T, ts_item, &buf) catch "error as_str";

            if (self.item_map.get(ts_item)) |item_id| {
                std.debug.print("  found {s} at id: {any}.\n", .{item_txt, item_id});
                return item_id;
            } else {
                const dup_item = try dupe_value(T, ts_item, self.allocator);
                try self.unique_items.append(dup_item);
                const new_id: u32 = @intCast(self.item_count() - 1);
                try self.item_map.put(ts_item, new_id);
                std.debug.print("  added item: {s} at id: {}\n", .{item_txt, new_id});
                return new_id;
            }
        }

        fn alloc_arrays(self: *Self) !void {
            // Allocate the dependents array.
            self.dependents = try self.allocator.alloc(ArrayList(u32), self.item_count());
            for (0..self.dependents.len) |i| {
                self.dependents[i] = ArrayList(u32).init(self.allocator);
            }
            // Allocate the incomings array.
            self.incomings = try self.allocator.alloc(u32, self.item_count());
            @memset(self.incomings, 0);
            // Allocate the visited array.
            self.visited = try self.allocator.alloc(bool, self.item_count());
            @memset(self.visited, false);
        }

        fn add_dependents(self: *Self) !void {
            for (self.dependencies.items) |dep| {
                const lead_id   = self.item_map.get(dep.leading);
                const dep_id    = self.item_map.get(dep.dependent);
                try self.add_dependent(lead_id.?, dep_id.?);
            }
            std.debug.print("  dependents: [", .{});
            for (self.dependents) |list| {
                std.debug.print(" {any} ", .{list.items});
            }
            std.debug.print(" ]\n", .{});
        }

        fn add_dependent(self: *Self, lead_id: u32, dep_id: u32) !void {
            var list_ptr = &self.dependents[lead_id];
            const found = std.mem.indexOfScalar(u32, list_ptr.items, dep_id);
            if (found == null) {
                try list_ptr.append(dep_id);
            }
        }

        fn add_incomings(self: *Self) !void {
            for (self.dependents) |list| {  // each item leads a list of dependents.
                for (list.items) |dep_id| { // all dep_id have one incoming from the leading item.
                    self.incomings[dep_id] += 1;    
                }
            }
            std.debug.print("  incomings:  {any}\n", .{self.incomings});
        }

    };

}

// Define a dependency between a leading item and a dependent item.
// The leading item needs to go first before the dependent item.
fn Dependency(comptime T: type) type {
    return struct {
        const Self = @This();
        leading:    T,
        dependent:  T,

        // Create an object with cloned values, whose memory allocated with the allocator.
        fn init(allocator: Allocator, leading: T, dependent: T) !Self {
            return Self {
                .leading = try dupe_value(T, leading, allocator),
                .dependent = try dupe_value(T, dependent, allocator),
            };
        }

        fn deinit(self: *Self, allocator: Allocator) void {
            free_value(T, self.leading, allocator);
            free_value(T, self.dependent, allocator);
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
        var buf: [16]u8 = undefined;
        const txt = value_as_str(T, value, &buf) catch "error as_str";
        std.debug.print("  free_value, pointer type value, {s}\n", .{txt});
        // Free the allocated memory for pointer type.
        allocator.free(value);
    } else {
        std.debug.print("  free_value, primitive type value, no need to free, {}\n", .{value});
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

