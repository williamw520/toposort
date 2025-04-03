
# TopoSort Algorithm

William Wong, 2025-04-02

The algorithm used in TopoSort is a variant to the Kahn's algorithm, 
but it works on sets instead of individual nodes.
Its goal is to find dependence-free node sets in topological order.
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

In a DAG graph, there exist some nodes which depend on no other nodes. 
These are the root nodes of the graph, where graph traversal begins.
These form the root set of the graph.

We define that when a node y depends on x, node y has an incoming link from x.
When node x is removed, the incoming link to y is removed as well.

Removing the nodes of a root set from the graph causes the remaining nodes
depending on them to have one less dependence, i.e. their incoming links are removed
and the incoming link count decremented.  For the nodes whose incoming links
reaching 0, they become the new root nodes as they depend on no one.

We observe that set A has no dependence on set B when all members of A have
no dependence on any member of B.

It follows that each root set removed during the iteration has no dependence
on any other root sets coming after it, thus the sequence of successively removed
root sets forms a topological order.

## Dependence Free Subsets

The nodes in a root set have no dependence among themselves since root nodes 
by definition depend on no other nodes.  These dependence free nodes in 
a root set allow parallel processing within the scope of the root set.

Subsequent root sets do depend on previous root sets

When the nodes of all the root sets are lining up in the order of the root sets,
they form a topological order, too.

## Cyclic Node Detection

A "rooted" list is used to track whether a node has become a root.
When traversing the dependents of a root node to find the next set of roots,
a dependent in the rooted list means it has already become a root
before.  That means a cycle exists in the graph linking an already rooted
node as a dependent for another node.

Instead of aborting, the traversing of the dependent of a root node can be 
merely skipped. This stops going into the cycle and allows the algorithm to
continue with the rest of the nodes.  A partial list of the topological order
nodes can be produced at the end.

After the main iteration, any nodes not in the "rooted" list can be classified
as parts of the cycles since they were not reachable due to the prior cycle 
skipping when traversing the dependents of root nodes.

