
# TopoSort Algorithm - Set Based Topological Sort

William Wong, 2025-04-02

The algorithm used in TopoSort is a variant to the Kahn's algorithm, 
but it works on sets instead of individual nodes.
Its goal is to find the dependence free node sets of a graph in topological order.
It also finds cyclic nodes as a side benefit.

## Overview

The main idea is to iteratively find the successive root sets of a graph after
removing them at each round.  Here's an outline of the algorithm.

1. Find the first root set of the graph.
2. Remove the nodes of the root set from the graph.
3. Find the next root set. Go to 2 until the graph is empty.

The successively removed root sets form a topological order. 
The nodes within each root set are dependence free in the set.
Further the nodes are in topological order when lined up in the order
of the root sets.

## Example

For a graph with nodes `{a, b, c, d, e, f}`, successively removed root sets look like:

```
{a, b} | {c, d, e, f}
{a, b} {d} | {c, e, f}
{a, b} {d} {c, e} | {f}
{a, b} {d} {c, e} {f}
```

## Rationale

By definition, a topological order of the nodes of a directed acyclic graph (DAG)
is a linear node arrangement that a node has no dependence on any other nodes coming after it.

For a directed acyclic graph, there exist some nodes which depend on no other nodes. 
These are the root nodes of the graph, where graph traversal begins.
These form the root set of the graph.

We define that when a node y depends on node x, node y has an incoming link from x.
When node x is removed, the incoming link to y is removed as well.

Removing the nodes of a root set from the graph causes the remaining nodes
depending on them to have one less dependence, i.e. their incoming links are removed
by one and the counts of incoming links decremented.  For the nodes whose incoming links
reaching 0, they become the new root nodes now as they depend on no one.

We observe that set A has no dependence on set B when all members of set A have
no dependence on any member of set B.

It follows that each root set removed during the iteration has no dependence
on any other root sets coming after it since its nodes have no dependence
on any nodes of the root sets coming after, thus the sequence of successively 
removed root sets forms a topological order.

## Dependence Free Subsets

The nodes in a root set have no dependence among themselves since root nodes 
by definition depend on no other nodes. The root sets become subsets of the graph
containing independent nodes.  The dependence free nodes in a subset allow 
parallel processing within the scope of the set.

Subsequent root sets do depend on the previous root sets, thus serialized
processing is still required among subsets following the topological order.

## Topological Sorting of Nodes

When the nodes of all the root sets are lining up in the topological order
of the root sets, they also form a topological order as well.

## Cyclic Node Detection

A "rooted" list is used to track whether a node has become a root.
When traversing the dependents of a root node to find the next set of roots,
a dependent found in the rooted list means it has become a root before.
That means a cycle exists in the graph linking an already rooted
node as a dependent for another node.

Instead of aborting, the traversing of the dependent node can be 
merely skipped. This stops going into the cycle and allows the algorithm to
continue with the rest of the nodes.  A partial list of the topological order
nodes will be eventually produced.

After the main iteration, any nodes not in the "rooted" list can be classified
as parts of the cycles since they are not reachable due to the prior cycle 
skipping logic when traversing the dependents of root nodes.

## Algorithm Detail

- For a graph with N nodes, assign each node a node id, ranging from 0 to N-1.

- Let dependents = [0..N](id list), array of lists of node id.
  Node ids are used as array index. 
  Each element corresponds to a node indexed by its node id. 
  Each element is a list of node id depending on the node.

- Let incomings = [0..N] of integer, array of the counts of the incoming links of the nodes.
  Node ids are used as array index. The array is used to classify nodes as being in the graph
  or been removed.

- Let rooted = [0..N] of boolean, array of flags indicating whether a node has become root.
  Node ids are used as array index.

- Let current_root_set = the list of node id of the current root set in the current round.

- Let next_root_set = the list of node id of the next root set in the next round.

- Let result = list holding the topologically sort sets.

- Find the initial root set by scanning the incomings array for 0 count entries.
  Collect the found node id and add them to current_root_set.

- Run the loop.
```
    while current_root_set is not empty
        add the current_root_set to result
        for each root_id in current_root_set
            rooted[root_id] = true
        for each root_id in current_root_set
            for each dep_node_id in dependents[root_id]
                if rooted[dep_node_id]
                    continue            // cycle detected; skip
                incomings[dep_node_id] -= 1
                if (incomings[dep_node_id] == 0
                    append dep_node_id to next_root_set
        swap current_root_set and next_root_set
        clear next_root_set
```
- After the loop the result has a list of node sets in topological order.

- To find the set of cyclic nodes, scan the rooted array.
  Any node has not been rooted is in a cycle.

