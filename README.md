# Toposort - Topological Sort on Dependency Graph

Toposort is a highly efficient Zig library for performing topological sort on dependency graph.  This small library is packed with the following features:

* Building dependency graph from dependency data.
* Performing topological sort on the dependency graph.
* Generating dependence-free subsets within the topological order.
* Cycle detection and cycle reporting.
* Support on different node types.

## Content

* [Installation](#installation)
* [Usage](#usage)
* [License](#license)

## Installation

1. Go to the [Releases](https://github.com/williamw520/toposort/releases) page and pick a release to add to your project.
Identify the file asset URL for the release version.  E.g. https://github.com/williamw520/toposort/archive/refs/tags/1.0.tar.gz

2. Use `zig fetch` to add the Toposort package to your Zig project. 
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

3. Update your `build.zig` with the lines for toposort.

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

4. The `.addImport("toposort")` call let your import the module into your Zig source files.

```zig
    const toposort = @import("toposort");
```

## Usage

Using of Toposort typically follows the following steps in your Zig source file.

1. Import
```zig
const toposort = @import("toposort");
const TopoSort = toposort.TopoSort;
```

2. Initialization and memory management.
```zig
    const T = u32;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{});
    defer tsort.deinit();
```

3. Add dependency data.
```zig
    try tsort.add(101, 102);    // node 102 depends on the leading node 101
    try tsort.add(102, 103);
    try tsort.add(101, 104);
```

4. Perform the topological sort
```zig
    const result = try tsort.sort();
```

5. Check for cycles
```zig
    if (result.has_cycle()) {
        for (result.get_cycle().items) |id| {
            const node = result.get_node(id);
            ...
        }
    }
```

6. Otherwise, process the sorted result for non-cyclical graph.
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
which fit in the overall topological order of all the nodes.


### Configurations

The `Toposort.init()` function takes in options for configuration. E.g.
```zig
    const T = u32;  // node data type
    var tsort = try TopoSort(T).init(allocator, .{
        verbose = true,
        max_range = 4000,
    });
```
Setting the `verbose` flag prints more processing messages.

The `max_range` property sets the maximum value of the node item value.
E.g. For node values ranging from 1, 2, 3, 20, 75, ... 100, 100 is the
maximum value. If all your node values are position integers, 
passing in a number type (u16, u32, u64, etc) for the node data type and 
setting the `max_range` let Toposort use a simplified data structure with
faster performance.  Building the dependency tree can be more than 3X faster. 
Compare the 3rd benchmark and 4th benchmark in tests.zig.

## Benchmarks

Toposort comes with some benchmark tests.  

Rnn `zig build test -Doptimize=ReleaseFast` to run the benchmarks.


## License

Toposort is [MIT licensed](./LICENSE).

## Further Reading

For more information on the Zig build system, check out these resources:

- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Build System Tricks](https://ziggit.dev/t/build-system-tricks/)
