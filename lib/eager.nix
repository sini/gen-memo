# propagateEager — the cut-heavy fast path for incremental rebuild (eager-push V-push).
#
# Rank-ordered eager-push propagate: recompute ONLY enqueued nodes over a producers-first rank
# domain; a node is enqueued iff its data changed or an in-cone dependency is enqueued AND
# moved; cut off on no-move. store = ctx.store // builtStore (the §4(B) carry: unmoved +
# non-cone deps come from priorStore).
# BYTE-IDENTICAL to propagate/build. ★ The TOPOLOGICAL propagation order and the AFFECTED
# post-filter are RTD 1983's (§4.3/§5) and are verified at the primary. "Eager push" is THIS
# LIBRARY'S OWN name for its own cut-heavy variant: the word does not occur in that paper, and
# the characterisation is not attributed to it.
#
# WHEN TO USE: localized (cut-heavy) edits — it HASHES AND FORCES only O(|AFFECTED|+frontier)
# nodes vs propagate's O(|cone|). Opt-in: `propagate` stays the general default.
#
# ★ THE AXIS IS THE HASH/FORCE COMPONENT, NOT THE RECOMPUTE COMPONENT, and the sentence above
# used to claim both. MEASURED: `propagate` and `propagateEager` share a recompute set — 3 = 3
# at both fixture sizes on BOTH fixture shapes, chain and reconvergent DAG, unit = the set of
# ids a poisoned `recompute` fires on. The mechanism is `needsEval` (lib/strategies.nix): a node
# `propagate` does not recompute is served from `base = ctx.store`, so its new hash EQUALS its
# trace hash and cannot move, and `propagate`'s recompute set therefore closes under the same
# "an enqueued dep moved" recursion this gate walks — while `propagate` HASHES EVERY CONE NODE
# to find that out. The eager gate's `enq d` conjunct short-circuits before the HASH, not before
# the recompute. SCOPED, not general: the equality breaks where `needsEval`'s other disjunct
# fires (a null trace hash), where `propagate` recomputes strictly more.
#
# Honest envelope (preconditions; out-of-envelope ⇒ use propagate):
#   - DATA-change only: `changes` replaces nodeData; EDGES ARE FIXED (cone over accessor' ==
#     cone over ctx.accessor), exactly like override.
#   - ACYCLIC cone: graph.coneRank requires it. This comment PREVIOUSLY claimed a cyclic cone
#     black-holes into Nix's uncatchable "infinite recursion" — MEASURED FALSE at the pinned
#     gen-graph revision (den-hoag-xyme): `coneRank` computes its cycle-check (topoOrderKahn)
#     BEFORE warming any node, and a cyclic cone throws a CATCHABLE, LOCATED refusal naming the
#     cycle (`gen-graph.coneRank: cyclic cone has no producers-first rank; cycles [...]`) — the
#     identical hazard build.nix/drivers.nix guard against, already discharged one layer down.
#     Nothing is ever recomputed or cached on that path (the throw fires before `rank.order` is
#     read), so Söderberg-Hedin 2013 §4.2's non-final-caching obligation and ADR-0008 item 2's
#     byte-parity definition both hold here BY CONSTRUCTION, with no guard owed at this site.
#     Cyclic stays in restabilize/runScc.
#   - COST: a constant-factor win on the EXPENSIVE axis (hash/force/alloc) for cut-heavy
#     edits; it still pays O(|cone|) cheap drive bookkeeping (rank + the two domain maps), so
#     it is NOT a total-work O(|AFFECTED|) bound (v3 minimality spike verdict: PARTIAL —
#     sub-cone on cut-heavy, no asymptotic minimality in pure substrate). That O(|cone|) bound
#     holds for the maps below and is what `test-eager-drive-is-domain-keyed` keeps true: the
#     drive tracks the shipped fold within 0.5 % at every size measured, while a
#     function-valued drive would be exponential.
{ prelude, graph, ... }:
let
  inherit (import ./hash.nix { }) hashGuarded hashMoved;
  inherit (import ./graph-view.nix { }) graphView;
in
{
  propagateEager =
    engine: ctx: changes:
    let
      changedIds = builtins.attrNames changes;
      accessor' = ctx.accessor // {
        nodeData = id: changes.${id} or (ctx.accessor.nodeData id);
      };
      graphOf = graphView accessor';
      cone = prelude.unique (changedIds ++ prelude.concatMap (graph.dependentsOf graphOf) changedIds);
      coneSet = prelude.genAttrs cone (_: true);
      rank = graph.coneRank graphOf cone;

      # The whole cone is handed to the engine as ONE domain and the eager cut is the
      # DECISION: `isClean` is the plane's answer and `recompute` is not called for a cut
      # node at all — reuse is the absence of the call (reference/schedule.nix). A clean
      # node is served from `base` = ctx.store, so its hash cannot move and the cut
      # propagates. `store = ctx.store // builtStore` is the §4(B) carry: unmoved and
      # non-cone deps come from the prior store.
      builtStore = engine.schedule {
        accessor = accessor';
        inherit (ctx) recompute;
        domain = rank.order;
        base = ctx.store;
        isClean = id: !enq.${id};
      };

      # ★ THE DRIVE IS A MAP OVER THE DOMAIN, NEVER A RECURSIVE FUNCTION. Nix memoises
      # THUNKS, not FUNCTION APPLICATIONS, so a `let`-bound `enq = id: … enq d …`
      # re-evaluates its whole recursion once per PATH and is exponential in cone depth
      # wherever paths reconverge — measured at 2,147,502,350 vs 20,113 nrFunctionCalls on
      # a 49-node reconvergent DAG, byte-parity-true in both arms. A `let` binding is
      # recursive in Nix, so `prelude.genAttrs` over the domain IS the knot: each node's
      # answer is a thunk, forced at most once, and the drive is linear again.
      # `ci/tests/purity.nix`'s `test-eager-drive-is-domain-keyed` pins the shape, because
      # no run-time cell can see it: the two forms produce equal stores, equal traces and
      # equal poison sets.
      #
      # Both maps also retire the per-round `builtins.seq` discipline the fold needed
      # rather than dropping it: `genAttrs` over a domain builds no `//`-chain, so the
      # thunk-chain C-stack overflow that discipline existed to prevent is gone by
      # construction.
      #
      # null-safe move test (unhashable ⇒ always-dirty, hash.nix); do NOT collapse to `!=`.
      moved = prelude.genAttrs rank.order (
        d: hashMoved (hashGuarded ctx.hashOf builtStore.${d}) (ctx.trace.${d}.hash or null)
      );

      # The eager gate: a node is enqueued iff its own data changed, or an IN-CONE
      # dependency is itself enqueued AND moved. The `coneSet ? ${d}` conjunct is what
      # keeps this total — `enq` is defined over the cone alone — and it is the same cone
      # restriction the shipped drain applied to its dependents; do NOT drop it. `moved`
      # sits BEHIND `enq` in a short-circuiting `&&`, so a cut node is never hashed either.
      enq = prelude.genAttrs rank.order (
        id:
        (changes ? ${id})
        || builtins.any (d: (coneSet ? ${d}) && enq.${d} && moved.${d}) (accessor'.dependencies id)
      );

      # ★ `domain = rank.order`, NOT `domain = cone`, and the difference is TOTALITY.
      # They are the same set (`coneRank`'s order is a sort of the cone), so the decision
      # is identical — but `genAttrs` forces its domain list first, which runs `coneRank`'s
      # acyclicity check and makes a cyclic cone throw the named, CATCHABLE refusal before
      # any `isClean` call. Under `domain = cone` that check is never forced and the
      # memoised knot closes with nothing to break it: `infinite recursion`, which escapes
      # `tryEval`. The order costs 1.4–1.7× the drive calls, and that is what buys the
      # refusal.
      affected = builtins.filter (id: enq.${id} && moved.${id}) rank.order;
      store = ctx.store // builtStore;
      trace' =
        ctx.trace
        // prelude.genAttrs affected (id: {
          deps = accessor'.dependencies id;
          hash = hashGuarded ctx.hashOf store.${id};
        });
    in
    {
      inherit store;
      trace = trace';
      accessor = accessor';
      inherit (ctx) recompute hashOf;
    };
}
