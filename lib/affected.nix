# affected — the dependent cone of an id (provenance query).
#
# Arntzenius 2016 Datafun: single-target reverse reachability (the dependent cone
# of `id`); `graph.dependentsOf` is the Datafun-derived query.
#
# A thin re-export of graph.dependentsOf over the ctx's accessor: everyone who
# transitively depends on `id` in the relation the evaluator publishes
# (single-target). `impactOf` is an alias. It promises EDIT-ROOT CONES: queried
# at an edit root, it is the set `override` must recompute when `id` changes.
# It does NOT promise every dependent of a node that is not an edit root. An
# evaluator that grows a node from a host has the grown node depend on its host
# and carries the host's read of its own grown node by the host's edit, not by
# an edge to the grown node; so queried at a grown member the answer can omit
# a reader whose cone the edit root already covers.
#
# Cost is graph.dependentsOf's own: Θ(n + E) to build the reverse index — it reads
# EVERY node's out-edges, reachable or not — then a BFS over that index costing
#   Θ( Σ_{u ∈ reach⁻ id} (1 + indeg u) )
# → reduces to the cone's size only where in-degree is BOUNDED, and never falls
# below the Θ(n + E) the index build pays whatever the cone's size; Θ(n²) on a
# complete DAG.
{ graph, ... }:
let
  inherit (import ./graph-view.nix { }) graphView;
  affected = ctx: id: graph.dependentsOf (graphView ctx.accessor) id;
in
{
  inherit affected;
  impactOf = affected;
}
