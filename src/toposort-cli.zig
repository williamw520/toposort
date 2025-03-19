
const std = @import("std");
const toposort = @import("toposort");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();
// const g_allocator = std.heap.page_allocator;


pub fn main() !void {
    std.debug.print("toposort.foo {}.\n", .{toposort.foo});

    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    var args = try CmdArgs.parse(g_allocator);
    defer args.deinit();
    try stdout.print("{s}, {s}, {s}, {}", .{ args.program, args.data_file, args.out_file, args.is_parallel });

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


test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
