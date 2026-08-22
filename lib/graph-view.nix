# graphView — the one crossing between this plane's vocabulary and gen-graph's.
#
# THE TWO NAMES DENOTE DIFFERENT OBJECTS, WHICH IS WHY THE CROSSING IS NAMED RATHER THAN LEFT
# INCIDENTAL. The accessor carries `dependencies`: the node-level dependency relation — Knuth
# (1968)'s D(T), coarsened from attribute instances onto nodes. gen-graph's operators bind `edges`:
# the generic scope->scope relation of van Antwerpen (2018) Fig. 1, which is the object that name
# properly denotes. A graph operator is indifferent to WHICH relation it walks — that indifference
# is what makes it generic — so the correspondence belongs at the boundary, stated once, rather
# than re-asserted at each of the twenty-one call sites where it would read as a coincidence.
#
# ★★★ THE ACCESSOR HAS TWO CONTRACTS, AND THEY DIFFER IN THE RELATION'S DOMAIN. This is the
# statement of record for both, and it is stated HERE because this is the one place the whole
# accessor crosses a boundary rather than being read a field at a time.
#
# The plane is PARAMETRIC OVER ITS DEPENDENCY ORACLE — Mokhov 2018's own parametricity, a rebuilder
# defined against a task description it does not construct. Two instantiations ship, they carry
# DIFFERENT DOMAINS for `dependencies`, and neither is a degenerate case of the other:
#
#   1. CALLER-BUILT MODE. The caller supplies the relation directly. It is TOTAL over the ids the
#      plane probes, INCLUDING ids outside `accessor.nodes`, and `nodes` means "the live set" —
#      never "every id the relation knows". The DISCOVERY FEATURE rests on exactly that totality:
#      `applyEdgeDelta`'s new-producer sub-build probes a new edge target BEFORE it is a member,
#      which is how a fresh producer is found and built at all, and `why`/`whyNot` walk the
#      relation from a caller-supplied id. This is behaviour ADR-0005/0008 carry forward, and it is
#      a contract rather than an accident: `ci/tests/structural.nix` builds a fixture whose `nodes`
#      is one id while its relation answers for three, because the feature cannot be exercised any
#      other way.
#
#   2. CONTRACTED MODE. A substrate hands the plane a relation that is the NORMALIZED UNION of a
#      structural half and a declared half, and that relation is FAIL-CLOSED: a non-member id is
#      refused BY NAME rather than answered. Its domain is exactly the evaluated node set.
#
# ★★★ THE MODES ARE DISJOINT BY CONSTRUCTION, WHICH IS WHY THIS IS A DOMAIN STATEMENT AND NOT A
# GUARD. A contracted accessor never legitimately meets a foreign id through `newEdges`, because
# the MEMBERSHIP CONTRACT BOUNDS EVERY ID AN EDGE NAMES: the structural half is refused by name at
# the projection when an endpoint is not a node of the evaluated graph, and the declared half is
# contracted upstream at minting, where an unresolved reference is refused (ADR-0016 r7) instead of
# travelling. An edge set drawn from that relation therefore names only members, so the walk that
# would probe a non-member has nothing to probe it WITH. A consumer-side membership check here
# would decide the same question a second time, at a site that guards a PATH rather than a
# CONSTRUCT — the shape the codomain ruling declined on its own grounds.
#
# ★★ AND THE BOUNDARY IS LOUD AT CONTACT, which is what makes this enforced documentation rather
# than prose that fails open. Cross the modes anyway — hand a contracted accessor to a discovery
# path — and the named membership refusal fires at the first probe and the operation aborts naming
# the id. Nothing swallows it into a default. `ci/tests/accessor-modes.nix` measures that: the
# refusal surfaces, and the same fixture under a caller-built relation completes.
#
# ★★★ THE ONE SILENT CELL, NAMED HERE RATHER THAN LEFT TO BE DISCOVERED. `provenance.nix` publishes
# two queries documented to agree BY CONSTRUCTION — they share `_verdict`, so the verdict BRANCHES
# cannot drift. That agreement holds WITHIN A MODE. It does not survive a cross-mode probe, because
# the two differ in their MEMBERSHIP ORACLE, and that is a different axis from the branches:
#
#   · `why` decides membership by WALKING the relation (`graph.canReach`), so under a contracted
#     accessor a foreign id ABORTS with the membership refusal.
#   · `whyFor` binds the cone once and decides membership by SET LOOKUP, so a foreign id simply
#     misses the cone and it answers `unaffected` — a plausible verdict about a node that does not
#     exist.
#
# That asymmetry is a written fact of this interface, not a defect awaiting repair: repairing it
# means deciding membership a second time inside the plane, which is the guard the ruling declined.
# `ci/tests/accessor-modes.nix` pins BOTH halves, so the pair cannot drift out of the documented
# shape unnoticed.
#
# ★ RE-ENTRY CONDITION, so this statement carries its own expiry. The disjointness above rests on
# every id an edge names being a member. If plane-side incremental EDIT SETS against contracted
# accessors are ever scoped — new nodes entering through deltas rather than through
# re-evaluation — then a contracted accessor meets ids outside its node set BY DESIGN, the two
# modes MEET, and this domain statement stops being sufficient. The question then returns as a real
# choice between guarding the consumer and reworking discovery, and it is owed a ruling rather than
# an edit here.
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
