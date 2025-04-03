
# TopoSort Algorithm

William Wong

The algorithm used in TopoSort is a variant to the Kahn's algorithm, 
with the additions on finding dependence-free subsets and finding cyclic nodes.

## Overview

The main idea is to iteratively find the successive root sets of the graph after
removing them at each round.  Here's a high level outline of the algorithm.

1. Find the first root set of the graph.
2. Remove the nodes of the root set from the graph.
3. Find the next root set. Go to 2 until the graph is empty.

The successively removed root sets form a topological order. 
The nodes within each root set are dependence-free in the root set.
Further the nodes are a topological order when lined up in the order
of the root sets.

## Rational

By definition, a topological order of the nodes of a directed acyclic graph (DAG)
is such that the nodes are linearly ordered in such a way that
a node has no dependence on any other nodes coming after it.

In the graph, there exist some nodes which depend on no other nodes. 
These are the root nodes of the graph, where traversal of the graph begins from them.
These form the inital root set.

We define that when a node y depends on x, node y has an incoming link from x.
When node x is removed, the incoming link to y is removed as well.

Removing the nodes of the root set from the graph causes the remaining nodes
depending on them to have one less dependence, i.e. their incoming links decremented.
For the nodes whose incoming links reaching 0, they become the new root nodes.

We define that set A has no dependence on set B when all members of A have
no dependence on any members of B.

It follows that each root set removed during the iteration has no dependence
on any other root sets coming after it, thus the sequence of successively removed
root sets forms a topological order.

By definition, the nodes in a root set have no dependence among themselves;
that's why they are selected as the root nodes to begin with.
When the nodes of all the root sets are lining up in the order of the root sets,
they form a topological order, too.

Further, the nodes in a root set are dependence free from each other, allowing
parallel processing within the scope of the root set.

A "rooted" list is used to track whether a node has become a root node.
When examining the dependents of a root node to find the next set of roots,
if a dependent is already in the rooted list, it means it has become a root
before.  That means a cycle exists in the graph linking an already rooted
node as a dependent for another node.

