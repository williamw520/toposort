# TopoSort - Set Based Topological Sort

TopoSort is a highly efficient Zig library for performing topological sort on dependency graph. 
It uses a novel set based approach for finding the topological order.
This small library is packed with the following features:

* Building dependency graph from dependency data.
* Performing set based topological sort on the graph.
* Partitioning the graph in topological ordered subsets.
* Generating dependence-free subsets for parallel processing.
* Generating topological order on the nodes.
* Cycle detection and cycle reporting.
* Support different node types.

[Algorithm description](./Algorithm.md)

## Content

* [Installation](#installation)
* [Usage](#usage)
  * [Memory Ownership](#memory-ownership)
  * [Configuration](#configuration)
  * [More Usage](#more-usage)
* [CLI Tool](#command-line-tool)
* [Benchmarks](#benchmarks)
* [License](#license)

## Installation  

Go to the [Releases](https://github.com/williamw520/toposort/releases) page.
Pick a release to add to your project.
Identify the file asset URL for the release version. 
E.g. https://github.com/williamw520/toposort/archive/refs/tags/1.0.2.tar.gz

Use `zig fetch` to add the TopoSort package to your Zig project. 
Run the following command to fetch the TopoSort package:
```shell
  zig fetch --save https://github.com/williamw520/toposort/archive/refs/tags/<VERSION>.tar.gz
```

`zig fetch` updates your `build.zig.zon` file with the URL with file hash added in the .dependency section of the file.

   ```diff
   .{
       .name = "my-project",
       ...
       .dependencies = .{
   +       .toposort = .{
   +           .url = "zig fetch https://github.com/williamw520/toposort/archive/refs/tags/<VERSION>.tar.gz",
   +           .hash = "toposort-...",
   +       },
       },
   }
   ```

Update your `build.zig` with the lines for toposort.

  ```diff
    pub fn build(b: *std.Build) void {
        ...
 +     const opts = .{ .target = target, .optimize = optimize };
 +     const toposort_module = b.dependency("toposort", opts).module("toposort");
        ...
        const exe = b.addExecutable(.{
            .name = "my_project",
            .root_module = exe_mod,
        });
 +     exe.root_module.addImport("toposort", toposort_module);
```

The `.addImport("toposort")` call let you import the module into your Zig source files.

```zig
const toposort = @import("toposort");
```


## Usage

Usage typically follows the following steps in your Zig source file.  

#### Import
```zig
const toposort = @import("toposort");
const TopoSort = toposort.TopoSort;
const SortResult = toposort.SortResult;
```

#### Initialization and memory management.
```zig
    const T = usize;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{});
    defer tsort.deinit();
```
The data type of the node value is provided as a comptime type to TopoSort(T).

#### Adding dependency data.
```zig
    try tsort.add(101, 102);    // node 102 depends on the leading node 101
    try tsort.add(102, 103);
    try tsort.add(101, 104);
```

#### Performing the topological sort
```zig
    const result = try tsort.sort();
```

#### Checking for cycles
```zig
    if (result.has_cycle()) {
        for (result.get_cycle_set().items) |id| {
            const cyclic_node = result.get_node(id);
            ...
        }
    }
```

#### Otherwise, process the sorted non-cyclic result
```zig
    const sets: ArrayList(ArrayList(T)) = result.get_sorted_sets();
    for (sets.items) |subset| {     // the node sets are in topological order
        for (subset.items) |node| { // nodes within each set are dependence free from each other.
            ...
        }
    }
```

TopoSort figures out the nodes that have no dependence with each other
in the linear order of the topological sequence and groups them together as subsets.
This allows you to run/process the nodes of each subset in parallel.

The subsets themselves are in topological order. If there's no need for 
parallel processing, the nodes in each subset can be processed sequentially,
which fit in the overall topological order of all the nodes.


### Memory Ownership

Nodes are passed in by value in `add()` and are stored by value in the TopoSort's Data struct.
For simple type like integer (e.g. u16, u32), the node values are simply copied.
For slice and pointer node type (e.g. []const u8), the memory for the nodes 
are not duplicated. Memory is owned and managed by the caller.


### Configuration

The `Toposort.init()` function takes in optional configurations. E.g.
```zig
    const T = usize;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{
        verbose = true,
        max_range = 4000,
    });
```
Setting the `verbose` flag prints internal messages while sorting.

The `max_range` property sets the maximum value of the node item value.
E.g. For node values ranging from 1, 2, 3, 20, 75, ... 100, 100 is the
maximum value. If all your node values are positive integers, 
passing in a number type (u16, u32, u64, etc) for the node data type and 
setting the `max_range` let TopoSort use a simpler data structure with
faster performance.  Building a dependency tree can be more than 3X or 4X faster. 
Compare the 3rd benchmark and 4th benchmark in tests.zig.


### More Usage

#### To use a slice/string for the node type,
```
    const T = []const u8;
    var tsort = try TopoSort(T).init(allocator, .{});
```

#### To get a list of topologically sorted nodes.
```
    const T = []const u8;
    var list = ArrayList(T).init(allocator);    // list to hold the returned nodes.
    defer list.deinit();
    for ((try result.get_sorted_list(&list)).items) |node| {
        ...
    }
```

#### To add dependency similar to the Makefile rule format,
Add the dependent node A to the leading B node.  A: B  
Add the dependent node B to the leading C node.  B: C  
Add the dependent node B to a list of leading nodes.  B: E F G  
```
    const T = []const u8;
    var tsort = try TopoSort(T).init(allocator, .{});
    try tsort.add_dep("A", "B");    // A: B
    try tsort.add_dep("B", "C");    // B: C
    try tsort.add_dep("B", "D");    // B: D
    try tsort.add_deps("B", &[_]T{ "E", "F", "G" });    // B: E F G
    
    var nodes = ArrayList(T).init(allocator);
    try nodes.append("E");
    try nodes.append("F");
    try nodes.append("G");
    try tsort.add_deps("B", nodes.items);
```

#### To add a graph in one shot in text string,
```
    var tsort = try TopoSort([]const u8).init(allocator, .{});
    try tsort.add_graph("(a b) (a c) (d) (c e f g)");
```
The format of the graph data is a series of "(dep lead)" rules in a string.
In the example above, `a` depends on `b`, `a` depends on `c`, `d` depends on none, 
and `c` depends on `e`, `f`, and `g`.

This can be called multiple times with different parts of the graphs to build the whole thing.

#### To traverse the list of nodes in the graph,
```zig
    for (result.get_nodes().items) |node| {
        ...
    }
```

#### To traverse the dependency graph recursively,
```zig
    const T = usize;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{});
    ...
    const result = try tsort.sort();
    visit_tree(result, null, result.get_root_set());

    fn visit_tree(result: SortResult(T), lead_id: ?u32, dependent_ids: ArrayList(u32)) {
        if (lead_id) |id| { // lead_id is optional since the root nodes have no leading nodes.
            const lead_node = result.get_node(id);
            ...
        }
        for (dependent_ids.items) |node_id| {
            const dependent_node = result.get_node(node_id);
            ...
            visit_tree(result, node_id, result.get_dependents(node_id));
        }
    }
```

## Command Line Tool

TopoSort comes with a command line interface (CLI) tool `toposort-cli`, 
which uses the TopoSort library internally.  The data file it used follows
the simple dependent rule format of Makefile. E.g. 
```
  A: B
  B: C D
  C: E F G
```

Sample invocations on the test data:

```
  zig-out/bin/toposort-cli --data data/data.txt
  zig-out/bin/toposort-cli --data data/data.txt --verbose
  zig-out/bin/toposort-cli --data data/data2.txt
  zig-out/bin/toposort-cli --data data/data_cycle1.txt
  zig-out/bin/toposort-cli --data data/data_cycle2.txt
  zig-out/bin/toposort-cli --data data/data_num.txt --int
```

Specify the whole graph in the command line.
```
  zig-out/bin/toposort-cli --graph "(a b) (b d) (b c) (c d)"
  zig-out/bin/toposort-cli --graph "(a b) (a c) (d) (c e f g)"
```

## Standalone Build

To build the project itself, git clone the repository, then run the standard zig build commands.
The binary output is in zig-out/bin/toposort-cli


```
zig build
```

This runs the CLI from the zig build directly.
```
zig build run -- --data data/data.txt
```

This runs the CLI with graph input on the command line.
```
zig build run -- --graph "(a b) (a c) (b d) (c d)"
```

## Benchmarks

TopoSort comes with some benchmark tests.  
 
Run `zig build test -Doptimize=ReleaseFast` to run the benchmarks.

Note that the benchmarks take a number of minutes to run, especially for the debug mode bulid.
Comment out some benchmarks in the test section of toposort.zig for faster run.

### Benchmark Runs

Benchmarks ran on a ThinkPad T14 Gen 2 (year 2021), with an AMD Ryzen 7 PRO 5850U CPU,
plugged-in with the max power plan, on a single core since the benchmarks are single threaded.

---
The first two sets of benchmarks check the effect of increasing the node counts in 10X factor, 
with 1 link between nodes. Notice the times scaling up in locked steps with the node counts.
The observation fits the asymptotic complexity predication of O(|N| + |E|).
See [Algorithm](./Algorithm.md).
```
Benchmark increasing node in 10X scale on branching 1, with max_range
    Add dep    10000 nodes      1 links, time:    0ms, 30478512 nodes/s,    32 ns/node.
       Sort    10000 nodes      1 links, time:    2ms,  4130729 nodes/s,   242 ns/node.
    Add dep   100000 nodes      1 links, time:    2ms, 36524877 nodes/s,    27 ns/node.
       Sort   100000 nodes      1 links, time:   16ms,  6142204 nodes/s,   162 ns/node.
    Add dep  1000000 nodes      1 links, time:   25ms, 39343405 nodes/s,    25 ns/node.
       Sort  1000000 nodes      1 links, time:  152ms,  6568506 nodes/s,   152 ns/node.

Benchmark increasing node in 10X scale on branching 1, no max_range
    Add dep    10000 nodes      1 links, time:    0ms, 15052533 nodes/s,    66 ns/node.
       Sort    10000 nodes      1 links, time:    1ms,  6421535 nodes/s,   155 ns/node.
    Add dep   100000 nodes      1 links, time:    7ms, 13353452 nodes/s,    74 ns/node.
       Sort   100000 nodes      1 links, time:   15ms,  6263513 nodes/s,   159 ns/node.
    Add dep  1000000 nodes      1 links, time:   99ms, 10048790 nodes/s,    99 ns/node.
       Sort  1000000 nodes      1 links, time:  155ms,  6435034 nodes/s,   155 ns/node.
```
---
The following benchmarks check the effect of increasing the node counts and the link counts
at the same time. Notice the times actually go down for more links and back up around 2000 links.
This is because the number of root sets goes down as more links fitted into the root sets,
so the number of root sets needed to be processed goes down.  Passed 2000 links, the time needed to 
process the links in each root set starts to dominate.
The times is still scaling up in locked steps with the node and link counts.
The observation fits the asymptotic complexity predication of O(|N| + |E|).
```
Benchmark increasing node and increasing link branching, with max_range
 Add + Sort    10000 nodes      2 links, time:    1ms, 11015156 nodes/s,    90 ns/node.
 Add + Sort   100000 nodes      2 links, time:   16ms, 11856236 nodes/s,    84 ns/node.
 Add + Sort  1000000 nodes      2 links, time:  163ms, 12261454 nodes/s,    81 ns/node.
 Add + Sort    10000 nodes     10 links, time:    1ms, 16649739 nodes/s,    60 ns/node.
 Add + Sort   100000 nodes     10 links, time:   10ms, 19924724 nodes/s,    50 ns/node.
 Add + Sort  1000000 nodes     10 links, time:  103ms, 19407715 nodes/s,    51 ns/node.
 Add + Sort    10000 nodes    100 links, time:    0ms, 21518333 nodes/s,    46 ns/node.
 Add + Sort   100000 nodes    100 links, time:    9ms, 22152123 nodes/s,    45 ns/node.
 Add + Sort  1000000 nodes    100 links, time:   91ms, 21815646 nodes/s,    45 ns/node.
 Add + Sort    10000 nodes   1000 links, time:    1ms, 18115942 nodes/s,    55 ns/node.
 Add + Sort   100000 nodes   1000 links, time:   10ms, 18555354 nodes/s,    53 ns/node.
 Add + Sort  1000000 nodes   1000 links, time:  108ms, 18410920 nodes/s,    54 ns/node.
 Add + Sort    10000 nodes   2000 links, time:    1ms, 14957968 nodes/s,    66 ns/node.
 Add + Sort   100000 nodes   2000 links, time:   13ms, 14565072 nodes/s,    68 ns/node.
 Add + Sort  1000000 nodes   2000 links, time:  137ms, 14512509 nodes/s,    68 ns/node.
 Add + Sort    10000 nodes   3000 links, time:    1ms, 19243721 nodes/s,    51 ns/node.
 Add + Sort   100000 nodes   3000 links, time:   15ms, 12721157 nodes/s,    78 ns/node.
 Add + Sort  1000000 nodes   3000 links, time:  161ms, 12353403 nodes/s,    80 ns/node.
 Add + Sort    10000 nodes   4000 links, time:    0ms, 22124383 nodes/s,    45 ns/node.
 Add + Sort   100000 nodes   4000 links, time:   18ms, 10958015 nodes/s,    91 ns/node.
 Add + Sort  1000000 nodes   4000 links, time:  192ms, 10407791 nodes/s,    96 ns/node. 
 Add + Sort    10000 nodes   5000 links, time:    1ms, 17566048 nodes/s,    56 ns/node.
 Add + Sort   100000 nodes   5000 links, time:   20ms,  9987086 nodes/s,   100 ns/node.
 Add + Sort  1000000 nodes   5000 links, time:  210ms,  9493224 nodes/s,   105 ns/node.
```
---
The following benchmarks examine the performance of the algorithm 
with increasing nodes on a fixed link branching (1K).
The times is scaling up linearly with the node counts.
```
Benchmark increasing nodes on fixed branching, with max_range
 Add + Sort    10000 nodes   1000 links, repeat 5, time:    1ms, 12857767 nodes/s,    77 ns/node.
 Add + Sort    20000 nodes   1000 links, repeat 5, time:    5ms,  7872404 nodes/s,   127 ns/node.
 Add + Sort    30000 nodes   1000 links, repeat 5, time:    5ms, 11648268 nodes/s,    85 ns/node.
 Add + Sort    40000 nodes   1000 links, repeat 5, time:    6ms, 12836517 nodes/s,    77 ns/node.
 Add + Sort    50000 nodes   1000 links, repeat 5, time:    8ms, 12175433 nodes/s,    82 ns/node.
 Add + Sort   100000 nodes   1000 links, repeat 5, time:   15ms, 12819214 nodes/s,    78 ns/node.
 Add + Sort   200000 nodes   1000 links, repeat 5, time:   30ms, 12955633 nodes/s,    77 ns/node.
 Add + Sort   300000 nodes   1000 links, repeat 5, time:   46ms, 12838140 nodes/s,    77 ns/node.
 Add + Sort   400000 nodes   1000 links, repeat 5, time:   46ms, 17231931 nodes/s,    58 ns/node.
 Add + Sort   500000 nodes   1000 links, repeat 5, time:   53ms, 18579224 nodes/s,    53 ns/node.
 Add + Sort   600000 nodes   1000 links, repeat 5, time:   64ms, 18557144 nodes/s,    53 ns/node.
 Add + Sort   700000 nodes   1000 links, repeat 5, time:   72ms, 19204589 nodes/s,    52 ns/node.
 Add + Sort   800000 nodes   1000 links, repeat 5, time:   85ms, 18731564 nodes/s,    53 ns/node.
 Add + Sort   900000 nodes   1000 links, repeat 5, time:   94ms, 19139920 nodes/s,    52 ns/node.
 Add + Sort  1000000 nodes   1000 links, repeat 5, time:  106ms, 18817277 nodes/s,    53 ns/node.
```
---
The following benchmarks check the increasing link counts on a fixed node count (1M).
The times for link count are flat until about 2000 links, which is when the link
processing starts to dominate the running time.
The times is scaling up linearly with the link counts.
The observation fits the asymptotic complexity predication of O(|N| + |E|).
Note that the time per node really suffers as each node has more links to process.
```
Benchmark increasing large link branching, with max_range
 Add + Sort  1000000 nodes    100 links, time:   89ms, 22341812 nodes/s,    44 ns/node.
 Add + Sort  1000000 nodes    200 links, time:   90ms, 22056212 nodes/s,    45 ns/node.
 Add + Sort  1000000 nodes    300 links, time:   93ms, 21413746 nodes/s,    46 ns/node.
 Add + Sort  1000000 nodes    400 links, time:   94ms, 21208053 nodes/s,    47 ns/node.
 Add + Sort  1000000 nodes    500 links, time:   96ms, 20661978 nodes/s,    48 ns/node.
 Add + Sort  1000000 nodes    600 links, time:  100ms, 19885538 nodes/s,    50 ns/node.
 Add + Sort  1000000 nodes   1000 links, time:  109ms, 18250731 nodes/s,    54 ns/node.
 Add + Sort  1000000 nodes   2000 links, time:  137ms, 14574640 nodes/s,    68 ns/node.
 Add + Sort  1000000 nodes   3000 links, time:  161ms, 12364630 nodes/s,    80 ns/node.
 Add + Sort  1000000 nodes   4000 links, time:  190ms, 10520593 nodes/s,    95 ns/node.
 Add + Sort  1000000 nodes   5000 links, time:  208ms,  9587661 nodes/s,   104 ns/node.
 Add + Sort  1000000 nodes   6000 links, time:  234ms,  8534598 nodes/s,   117 ns/node.
 Add + Sort  1000000 nodes  10000 links, time:  337ms,  5933957 nodes/s,   168 ns/node.
 Add + Sort  1000000 nodes  20000 links, time:  619ms,  3229246 nodes/s,   309 ns/node.
 Add + Sort  1000000 nodes  30000 links, time:  847ms,  2360065 nodes/s,   423 ns/node.
 Add + Sort  1000000 nodes  40000 links, time: 1074ms,  1861957 nodes/s,   537 ns/node.
 Add + Sort  1000000 nodes  50000 links, time: 1309ms,  1526782 nodes/s,   654 ns/node.
 Add + Sort  1000000 nodes  60000 links, time: 1461ms,  1368239 nodes/s,   730 ns/node.
 Add + Sort  1000000 nodes 100000 links, time: 2387ms,   837647 nodes/s,  1193 ns/node.
 Add + Sort  1000000 nodes 200000 links, time: 4535ms,   440982 nodes/s,  2267 ns/node.
 Add + Sort  1000000 nodes 300000 links, time: 5224ms,   382826 nodes/s,  2612 ns/node.
 Add + Sort  1000000 nodes 400000 links, time: 4754ms,   420658 nodes/s,  2377 ns/node.
 Add + Sort  1000000 nodes 500000 links, time: 7339ms,   272490 nodes/s,  3669 ns/node.
```
---

## License

TopoSort is [MIT licensed](./LICENSE).

## Further Reading

For more information on the Zig build system, check out these resources:

- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Build System Tricks](https://ziggit.dev/t/build-system-tricks/)
