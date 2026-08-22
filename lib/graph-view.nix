# graphView — the one crossing between this plane's vocabulary and gen-graph's.
#
# THE TWO NAMES DENOTE DIFFERENT OBJECTS, WHICH IS WHY THE CROSSING IS NAMED RATHER THAN LEFT
# INCIDENTAL. The accessor carries `dependencies`: the node-level DECLARED dependency relation —
# Knuth (1968)'s D(T), coarsened from attribute instances onto nodes. gen-graph's operators bind
# `edges`: the generic scope->scope relation of van Antwerpen (2018) Fig. 1, which is the object
# that name properly denotes. A graph operator is indifferent to WHICH relation it walks — that
# indifference is what makes it generic — so the correspondence belongs at the boundary, stated
# once, rather than re-asserted at each of the twenty-one call sites where it would read as a
# coincidence.
#
# THE VIEW IS TOTAL OVER THE ACCESSOR, NOT A TWO-FIELD PROJECTION. The partition and ordering
# operators (`condensation`, `coneRank`) take the accessor positionally and read their fields
# internally, so a projection naming the fields it thought they wanted would break silently on the
# next field one of them reads. Passing the accessor through and adding the bound name cannot.
#
# `dependencies` stays the authoritative name: this record is an ARGUMENT constructed at a call
# boundary, never a second accessor, and nothing in the plane reads `edges` back off it.
{ }:
{
  graphView = accessor: accessor // { edges = accessor.dependencies; };
}
