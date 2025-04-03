
# TopoSort Algorithm

There're some interests in knowing the algorithm behind TopoSort doing the topological sort.
Here's an overview.

The algorithm used in TopoSort is a variant to the Kahn's algorithm, 
with the additions on finding dependence-free subsets and finding the cyclic nodes.

## Overview

The main idea is to iteratively find the root sets of the graph after
successive removal of the root sets.  Here's a high level outline of the algorithm.

1. Find the first root set of the graph.
2. Remove the nodes of the root set from the graph.
3. Find the next root set. Go to 2 until the graph is empty.

The successive root sets form a topological order.

## Rational

By definition, a topological order of the nodes of a graph means that
a node has no dependence on any other nodes come after it.

As such, the root set of a graph consists of nodes that have no dependence 
on any other nodes in the graph. It's called the root set because traversal
of the graph can start from the nodes in it.

Removing the root nodes from the graph produces a new set of root nodes since 
the ones depending on the old root nodes now have one less dependence.
For the remaining nodes that have no dependence, they become the new root nodes.

We define a set A has no dependence on another set B when A's members have
no dependence on any members of B.

It follows that each root set has no dependence on any other root sets come after it,
thus forming a topological order.

Since the nodes in a root set have no dependence among themselves, when the nodes
of the root sets are lining up by the root sets, they form a topological order, too.

Further, the nodes in a root set are dependence free from each other, allowing
parallel processing within the scope of the root set.
