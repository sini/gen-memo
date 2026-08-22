# Fixture constructors for the PLANE'S accessor shape.
#
# gen-graph's `mkGraph` builds a GRAPH: a record whose relation is named `edges`, the generic
# scope->scope relation its operators bind. The plane's accessor is a different object — its
# relation is `dependencies`, the declared node-level dependency relation. The two were shape-
# identical until the names were separated, which is precisely why fixtures reached for `mkGraph`
# and nothing noticed: a coincidence of shape read as an identity of kind.
#
# ★ THE `edges` FIELD IS REMOVED RATHER THAN LEFT ALONGSIDE, AND THAT IS THE WHOLE POINT OF THIS
# FILE. A fixture handing the plane a record carrying BOTH names would keep passing if some plane
# path still read `.edges` — which is the one defect class a relation rename can introduce, masked
# by the very instrument that exists to catch it. Removing the old name makes any missed read fail
# loudly instead.
{ graph }:
rec {
  # planeOf — adapt any gen-graph graph record (its own `fixtures`, or anything built by its
  # constructors) to the plane's accessor shape.
  planeOf = g: builtins.removeAttrs g [ "edges" ] // { dependencies = g.edges; };

  # The common case: build one from an edge list in the same call.
  mkPlaneAccessor = args: planeOf (graph.mkGraph args);

  # graphOf — the crossing back, for the handful of cells that call a gen-graph operator DIRECTLY
  # as an oracle against a plane result.
  #
  # ★ DEFINED HERE RATHER THAN IMPORTED FROM `lib/graph-view.nix`, DELIBERATELY. Those cells assert
  # that the plane's answer equals gen-graph's over the same relation; an oracle that reached for
  # the subject's own adapter would go green on a defect inside that adapter, which is the one
  # place a relation rename is most likely to put one.
  graphOf = a: builtins.removeAttrs a [ "dependencies" ] // { edges = a.dependencies; };
}
