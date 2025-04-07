
# TopoSort Algorithm - Set Based Topological Sort

William Wong, 2025-04-02

The algorithm used in TopoSort produces a linear arranagement of sets of the nodes 
of a graph in topological order, where the nodes in each set are dependence free 
within the set. Further the nodes when lined up in the linear arrangement according 
to the order of the sets are also in topological order.

It is a variant of the Kahn's algorithm, but it works on sets instead of individual nodes.
It also finds the cyclic nodes as a side benefit.

## Overview

The main idea is to iteratively find the successive root sets of a graph after
removing each set at each round.  Here's an outline of the algorithm.

1. Find the first root set of the graph.
2. Remove the nodes of the root set from the graph.
3. Find the next root set.  Go to 2 until there's no more root node.

The successively removed root sets form a topological order. 
The nodes within each root set are dependence free in the set.

## Example

Given a graph with nodes `{a, b, c, d, e, f}` and with the dependency pairs of 
`(a -> d) (b -> d) (d -> c) (d -> e) (e -> f)`, where `{a, b}` is the first root set,
successively removing the root sets look like:

```
{a, b} | {c, d, e, f}
{a, b} {d} | {c, e, f}
{a, b} {d} {c, e} | {f}
{a, b} {d} {c, e} {f} |
```

The sets `{a, b}`, `{d}`, `{c, e}`, `{f}` form a new graph, with the pairs of the sets 
(`{a, b}` -> `{d}`), (`{d}` -> `{c, e}`), (`{c, e}` -> `{f}`) forming the dependence links between the sets. 
The final order of the sets is a topological order since preceding sets have no 
dependence on any of the sets coming after. Also the nodes of the preceding sets 
have no dependence on any nodes in the sets coming after.

## Rationale

Definition 1: A topological order of the nodes of a directed acyclic graph (DAG)
is a linear node arrangement that each node has no dependence on any other nodes coming after it.

Definition 2: When a node y depends on node x, node y has an incoming link from x, 
i.e. (x -> y). When node x is removed, the incoming link to y is removed as well.

Definition 3: A root node in a graph is one that depends on no other nodes,
i.e. it has no incoming link from others.

Definition 4: A root set of a graph is a set consisting of only the root nodes,
i.e. its members have no dependence on any remaining nodes in the graph.

Definition 5: A set X has no dependence on the set Y when every member of set X has
no dependence on any member of set Y. I.e. { x | x of X } -> { y | y of Y }, given
none of y -> x.

By the definition of a directed acyclic graph, there exist some nodes which depend on 
no other nodes. E.g. `a` and `b` above. These are the root nodes of the graph [def 3], 
where graph traversal begins. These form the root set of the graph [def 4]. E.g. `{a, b}`.

Removing the nodes of a root set from the graph causes the remaining nodes
depending on them to have one less dependence, i.e. their incoming links are removed
by one and their counts of incoming links decremented.  The nodes with incoming links
reaching 0 become the new root nodes now as they depend on no one [def 3].
The new root nodes form for a new root set [def 4].  E.g. `{d}` above after the first round.

It follows that each root set removed during the iteration has no dependence
on any other root sets coming after it since its nodes have no dependence
on the remaining nodes in the graph, which forms the subsequent root sets. [def 5].

The successively removed root sets form a new graph with a dependency relationship
where each preceding set has no dependence on the sets coming after. [def 5].
The sequence of successively removed root sets in the new graph forms a topological order. [def 1].

Q.E.D.

### Dependence Free Subsets

The nodes in a root set have no dependence among themselves since root nodes 
by definition depend on no other nodes [def 3]. The dependence free nodes in a set
allow parallel processing within the scope of the set.

Subsequent root sets do depend on the previous root sets, thus serialized
processing is still required among root sets following the topological order.

### Topological Sorting of Nodes

When the nodes of all the root sets are lining up in the topological order
of the root sets, they also form a topological order as well. Since the sets
are in topological order, by [def 5] the nodes in the preceding set have no
dependence on the following sets, thus the nodes are in topological order [def 1].

## Cyclic Node Detection

A "rooted" list is used to track whether a node has become a root.
When examining the immediate dependents of a root node to find the next set of roots,
a dependent node found in the rooted list means it has become root before.
That means a cycle exists in the graph linking an already rooted
node as a dependent to another node.

Instead of aborting the run, the traversing of the dependent node can be 
merely skipped. This stops going into the cycle and continues with the rest of the nodes.
A partial list of the topological order sets will be produced.

After the main iteration, any node not in the "rooted" list is part of a cycle
since it's not reachable due to the prior cycle skipping logic.

## Algorithm Detail

- For a graph with N nodes, assign each node a node id, ranging from 0 to N-1.

- Let dependents = [0..N](id list), array of lists of node id.
  Each element of the array corresponds to a node indexed by its node id. 
  Each element is a list of node id depending on the node.

- Let incomings = [0..N] of integer, array of counts of the incoming links of the nodes.
  Node ids are used as array index. Count of 0 means the node has been removed from the graph.

- Let rooted = [0..N] of boolean, array of flags indicating whether a node has become root.
  Initialize it to all falses. Node ids are used as array index.

- Let current_root_set = list of id, list of node id of the current root set in the current round.

- Let next_root_set = list of id, the list of node id of the next root set in the next round.

- Let result = list of sets, holding the topologically sort sets. Initialize it to empty.

- Find the initial root set by scanning the incomings array for 0 count entries.
  Collect the found node id and add them to current_root_set.

- Run the loop.
```
    while current_root_set is not empty         [1]
        append the current_root_set to result
        for each root_id in current_root_set    [2]
            rooted[root_id] = true
        for each root_id in current_root_set    [3]
            for each dep_node_id in dependents[root_id]    [4]
                if rooted[dep_node_id]
                    continue            // cycle detected; skip
                incomings[dep_node_id] -= 1
                if incomings[dep_node_id] == 0
                    append dep_node_id to next_root_set
        swap current_root_set and next_root_set
        clear next_root_set
```
- After the loop the result has a list of node sets in topological order.

- Scan the rooted array to find the set of cyclic nodes.
  Any node that has not been rooted is in a cycle.

## Complexity Analysis

The time complexity of the algorithm is O(|N| + |L|) for acyclic graphs, 
where |N| is the number of nodes and |L| is the number of links. 

The run count of `[1]` above is the number of root sets found in the graph, 
and the run counts of `[2]` and `[3]` are the number of nodes in each root set.
The total run count of them is |`[1]`| * (|`[2]`| + |`[3]`|), which is in 
the order of the total number of nodes in the root sets.

The root sets partition the graph, thus the total number of nodes in
all the root sets is the number of nodes in the graph. Thus the complexity
of `[1]`, `[2]`, and `[3]` is O(|N|).

The run count of `[4]` is the number of links in each root node only, not
the number of links for every node. The number of links of all root sets
added up to be in the order of the total links.  The complexity is O(|L|).

Thus the overal runtime complexity is O(|N| + |L|).

The space complexity of the algorithm is O(|N| + |L|) for acyclic graphs.
We need O(|N|) for storing the various |N| lengh arrays, and need O(|L|)
to store the `dependents` array.

Note that for the degenerate case of a complete graph where every node
depends on every other node, the time complexity is O(|N|^2).

The space complexity is also O(|N|^2) since every element of the `dependents` 
array has |N| nodes.

