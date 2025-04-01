# Toposort - Topological Sort on Dependency Graph

Toposort is a highly efficient Zig library for performing topological sort on dependency graph.  This small library is packed with the following features:

* Building dependency graph from dependency data.
* Performing topological sort on the dependency graph.
* Generating dependence-free subsets within the topological order.
* Cycle detection and cycle reporting.
* Support different node types.


## Content

* [Installation](#installation)
* [Usage](#usage)
  * [Memory Ownership](#memory-ownership)
  * [Configurations](#configurations)
  * [Other Usage](#other-usage)
* [CLI Tool](#command-line-tool)
* [Benchmarks](#benchmarks)
* [License](#license)

## Installation  

Go to the [Releases](https://github.com/williamw520/toposort/releases) page.
Pick a release to add to your project.
Identify the file asset URL for the release version.  E.g. https://github.com/williamw520/toposort/archive/refs/tags/1.0.tar.gz

Use `zig fetch` to add the Toposort package to your Zig project. 
Run the following command to fetch the Toposort package:
```shell
  zig fetch https://github.com/williamw520/toposort/archive/refs/tags/<VERSION>.tar.gz --save
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
    const T = u32;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{});
    defer tsort.deinit();
```

#### Add dependency data.
```zig
    try tsort.add(101, 102);    // node 102 depends on the leading node 101
    try tsort.add(102, 103);
    try tsort.add(101, 104);
```

#### Perform the topological sort
```zig
    const result = try tsort.sort();
```

#### Check for cycles
```zig
    if (result.has_cycle()) {
        for (result.get_cycle().items) |id| {
            const node = result.get_node(id);
            ...
        }
    }
```

#### Otherwise, process the sorted non-cyclical result
```zig
    const sorted_sets: ArrayList(ArrayList(T)) = result.get_sorted_sets();
    for (sorted_sets.items) |subset| { // the node sets are in topological order
        for (subset.items) |node| {    // nodes within each set are dependency free within the set.
            ...
        }
    }
```

Toposort figures out the nodes that have no dependency with each other
in the linear order of the topological sequence, and groups them together as subsets.
This allows you to run/process the nodes of each subset in parallel.

The subsets themselves are in topological order. If there's no need for 
parallel processing on the nodes, the nodes in each subset can be processed sequentially,
which fit in the overall topological order of all nodes.


### Memory Ownership

Nodes are passed in by value and are stored by value in the Toposort struct.
For simple type like integer (e.g. u16, u32), the node values are simply copied.
For slice and pointer node type (e.g. []const u8), the memory for the nodes 
are not duplicated. Memory is owned and managed by the caller.


### Configurations

The `Toposort.init()` function takes in options for configuration. E.g.
```zig
    const T = u32;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{
        verbose = true,
        max_range = 4000,
    });
```
Setting the `verbose` flag prints more internal messages.

The `max_range` property sets the maximum value of the node item value.
E.g. For node values ranging from 1, 2, 3, 20, 75, ... 100, 100 is the
maximum value. If all your node values are position integers, 
passing in a number type (u16, u32, u64, etc) for the node data type and 
setting the `max_range` let Toposort use a simpler data structure with
faster performance.  Building the dependency tree can be more than 3X faster. 
Compare the 3rd benchmark and 4th benchmark in tests.zig.


### Other Usage

#### To use a slice/string for the node type,
```
    const T = []const u8;   // node data type
    var tsort = try TopoSort(T).init(allocator, .{});
```

#### To traverse the list of nodes in the graph,
```zig
    for (result.get_nodes().items) |node| {
        ...
    }
```

#### To traverse the dependency graph recursively,
```zig
    const SortResult = toposort.SortResult;
    const T = u32;  // node data type
    visit_tree(result, null, result.get_root_set_id());

    fn visit_tree(result: SortResult(T), lead_id: ?u32, dependent_ids: ArrayList(u32)) {
        if (lead_id) |id| {
            const lead_node = result.get_node(lead_id);
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

Toposort comes with a command line interace (CLI) tool - toposort-cli, 
which uses the Toposort library internally.  The data file it used follows
the simple dependent rule specification of Makefile. E.g. 
```
  A: B
  B: C D
  C: E F G
```

Sample invocations:

```
  zig-out/bin/toposort-cli --data data/data.txt
  zig-out/bin/toposort-cli --data data/data.txt --verbose
  zig-out/bin/toposort-cli --data data/data2.txt
  zig-out/bin/toposort-cli --data data/data_cycle1.txt
  zig-out/bin/toposort-cli --data data/data_cycle2.txt
  zig-out/bin/toposort-cli --data data/data_num.txt --int
```

## Benchmarks

Toposort comes with some benchmark tests.  

Rnn `zig build test -Doptimize=ReleaseFast` to run the benchmarks.


## License

Toposort is [MIT licensed](./LICENSE).

## Further Reading

For more information on the Zig build system, check out these resources:

- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Build System Tricks](https://ziggit.dev/t/build-system-tricks/)
