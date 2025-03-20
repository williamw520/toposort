
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;


pub fn TopoSort(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator:  Allocator,
        ts_items:   ArrayList(T),       // the list of unique items.
        dep_counts: ArrayList(u32),     // counts of dependents of each item.

        pub fn init(allocator: Allocator) !*Self {
            const obj_ptr = try allocator.create(Self);
            obj_ptr.* = Self {
                .allocator = allocator,
                .ts_items = ArrayList(T).init(allocator),
                .dep_counts = ArrayList(u32).init(allocator),
            };
            return obj_ptr;
        }

        pub fn deinit(self: *Self) void {
            for (self.ts_items.items, 0..) |item, index| {
                std.debug.print("  free item: '{s}', index: {}\n", .{item, index});
                self.allocator.free(item);
            }
            defer self.ts_items.deinit();
            defer self.dep_counts.deinit();
        }

        pub fn count(self: *Self) usize {
            return self.ts_items.items.len;
        }

        pub fn add(self: *Self, dependent: T, required: T) !void {
            std.debug.print("add(), dependent: '{s}' => required: '{s}'\n", .{dependent, required});
            const dependent_id = try self.add_item(dependent);
            const required_id = try self.add_item(required);
            std.debug.print("  dependent_id: {} => required_id: {}\n", .{dependent_id, required_id});
        }

        fn add_item(self: *Self, ts_item: T) !u32 {
            for (self.ts_items.items, 0..) |item, id| {
                if (equal(T, item, ts_item)) {
                    std.debug.print("  found '{s}' at id: {}; skip.\n", .{ts_item, id});
                    return @intCast(id);
                }
            }            
            const id = self.count();
            const dup = try clone(T, self.allocator, ts_item); 
            try self.ts_items.append(dup);
            try self.dep_counts.append(0);
            std.debug.print("  added item: '{s}' at id: {}\n", .{ts_item, id});
            return @intCast(id);
        }

    };
    
}

fn clone(comptime T: type, allocator: std.mem.Allocator, value: T) !T {
    if (@typeInfo(T) == .Pointer) { 
        // Dynamically allocated memory (e.g., strings, slices).
        return try allocator.dupe(@typeInfo(T).Pointer.child, value);
    } else {
        // Primitive values and structs with no heap allocation.
        return value;
    }
}

fn equal(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .Pointer) {
        return std.mem.eql(@typeInfo(T).Pointer.child, a, b);
    } else {
        return a == b;
    }
}

