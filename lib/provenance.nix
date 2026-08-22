# provenance — the pure read layer over the verifying trace + adg reachability.
#
# Zero recompute, zero force-order observation: support/why/whyNot answer
# "what justifies this value" and "would an override touch this node" purely from
# ctx.trace + gen-graph queries over ctx.accessor.
#
#   support : the transitive declared PRODUCERS of a node — Acar 2002 adg (§4.4)
#     read in the IN-EDGE / BACKWARD direction (the adg itself is forward
#     source→target; support is the dual of `affected`). Reads the trace SNAPSHOT
#     deps so it stays consistent with the committed override. Acar §4.4 read
#     backward is the WHOLE of what this operator is; there is no second source.
#
#     ★ THE RADUL CITATION IS DELETED RATHER THAN QUALIFIED. It read "Only
#     NAME-faithful to Radul 2009 §6.1 support-set (no TMS, no merge-lattice, no
#     worldviews)" — and the disclaimer was accurate, which is exactly the problem:
#     what it disclaimed away was the paper's object. Radul §6.1 is *Dependencies
#     for Provenance*, whose support set is a minimal-premise set maintained by a
#     TMS over a merge lattice; ours is the structural declared-edge producer set,
#     computed by reachability and minimal in nothing. A citation whose own body
#     says the cited mechanism is absent is not provenance for anything — it is a
#     name borrowed for a word, and it survives compaction as a claim of descent
#     nobody re-checks. `support` is a NAME COLLISION with Radul's, not a debt.
#
#   why : the verdict an override of `changedId` would produce for `id`. Acar 2002
#     §7 read-rule, reframed: l∈C → recomputed, cmp-unchanged → cutoff, l∉C →
#     unaffected. `graph.canReach (graphView ctx.accessor) id changedId` is the single
#     Θ( Σ_{u ∈ reach id} (1 + outdeg u) ) verdict fast path — reducing to the
#     cone's size only at BOUNDED out-degree, Θ(n²) on a complete DAG, since the
#     operator re-reads `edges` at every visit (forward edges — NOT transposed:
#     dependentsOf/canReach already traverse consumer→producer directly).
#     `graph.pathsBetween` (exponential worst case) is reserved for explain-mode +
#     the cutoff overlay.
#
#   whyNot : the negative operator query — the reason `id` was not recomputed, as a
#     TOTAL record over all three verdicts (see the definition; the recomputed case
#     used to answer with an absence).
#
#   whyFor / whyNotFor : the AMORTIZED DUALS, curried on `changedId`. The membership
#     decision is loop-invariant across the ids of one change, so a caller asking it
#     of many ids binds the cone once (via `dirtySet`) and spends it, instead of
#     issuing one forward query per id. ★ This line cited "Arntzenius 2016 Datafun
#     reverse reachability" and does not any more: `reverse` occurs 0 times in that
#     paper (live controls in the same run: `monotone` 48, `semilattice` 41), and
#     `reachability` once, in a motivating aside. The cone is gen-graph's operator.
#     `why`/`whyNot` are UNCHANGED and keep the point query — the amortization is a
#     decision the CALLER makes, never a cost imposed on the caller asking once.
#
# Dependency convention: accessor.dependencies id = ids `id` depends on
# (consumer→producer); an override of `changedId` recomputes its dependent cone, i.e.
# every `id` that can REACH `changedId` over forward edges.
{ prelude, graph, ... }@args:
let
  sort = builtins.sort builtins.lessThan;

  # The cone operator, imported directly rather than reached through the library
  # value: one definition of the dependent cone, shared by the dual below.
  inherit (import ./dirtySet.nix args) dirtySet;
  inherit (import ./graph-view.nix { }) graphView;

  # support : BuiltCtx -> id -> [id]
  # Transitive declared producers of `id`, sorted, `id` excluded. The relation is read
  # from the trace snapshot (falling back to the live accessor for any id the
  # trace has no entry for) so support is consistent with the committed override.
  # reachableFrom already excludes the start node.
  support =
    ctx: id:
    sort (
      # The `edges` key is gen-graph's own parameter name; the relation supplied for it
      # is this plane's trace-or-declared reading. Two vocabularies meet on one line, so
      # neither name is a typo for the other.
      graph.reachableFrom {
        edges = id': ctx.trace.${id'}.deps or (ctx.accessor.dependencies id');
      } id
    );

  # supportDirect : the depth-1 declared producers (sorted) — the immediate
  # in-edges from the trace snapshot, without the transitive closure.
  supportDirect = ctx: id: sort (ctx.trace.${id}.deps or (ctx.accessor.dependencies id));

  # _verdict : BuiltCtx -> { changedId; cutoffs } -> (id -> bool) -> id -> WhyResult
  #   WhyResult = { verdict = "unaffected"; }
  #             | { verdict = "recomputed"; paths :: [[id]]; }   (paths only in explain/overlay)
  #             | { verdict = "cutoff"; cutNodes :: [id]; paths :: [[id]]; }
  #
  # THE VERDICT, WITH THE l∈C DECISION AS ITS ONLY PARAMETER. Acar 2002 §7 read-rule:
  # l∈C → recomputed, cmp-unchanged → cutoff, l∉C → unaffected — the rule is the same
  # whoever decides membership. The entry points below hand it different oracles (a
  # forward point query, or a cone bound once) and differ in nothing else HERE; a
  # second copy of these three branches would make the two answers agree by
  # coincidence rather than by construction.
  #
  # ★★★ THE SCOPE OF THAT AGREEMENT, STATED BECAUSE IT IS NOT UNCONDITIONAL. Sharing
  # this function pins the BRANCHES; it says nothing about the DOMAIN each oracle
  # accepts, and the two oracles differ there. Against a fail-closed accessor — the
  # substrate-contracted mode, whose relation refuses a non-member by name — an id
  # that is not a node splits them:
  #
  #   · `why` walks the relation through `graph.canReach`, meets the refusal, and
  #     ABORTS naming the id.
  #   · `whyFor` decides membership by lookup in a cone bound once, so the same id
  #     misses the cone and it answers `unaffected` — a plausible verdict about a
  #     node that does not exist.
  #
  # This is a WRITTEN FACT of the interface rather than a defect queued for repair:
  # closing it means deciding membership a second time inside the plane, which is the
  # consumer-side guard the accessor-domain ruling declined. The full statement of the
  # two contracts lives at `graph-view.nix`, and `ci/tests/accessor-modes.nix` pins
  # both halves so the pair cannot quietly drift out of the documented shape.
  _verdict =
    ctx:
    { changedId, cutoffs }:
    member: id:
    if !(member id) then
      # l∉C — no forward path id → changedId.
      { verdict = "unaffected"; }
    else if cutoffs == { } then
      # Verdict-only fast path: in the cone with no cutoff overlay ⇒ recomputed,
      # never synthesize an unwitnessed cutoff (a missing/absent overlay is pure
      # topological why).
      { verdict = "recomputed"; }
    else
      # Explain / cutoff-overlay mode: enumerate the acyclic paths id → changedId.
      # A path's INTERIOR (RTD-style cmp-unchanged cut points) is the nodes strictly
      # between id and changedId; changedId is NEVER an interior node (you cannot cut
      # the change origin). interior p = prelude.init (prelude.tail p): tail drops `id`, init
      # drops `changedId` — a direct edge [id, changedId] has interior [].
      let
        paths = graph.pathsBetween (graphView ctx.accessor) id changedId;
        # THE ORIGIN'S SELF-PATH IS THE SINGLETON, AND ITS INTERIOR IS EMPTY BY THE
        # DEFINITION ABOVE, not by a carve-out: `pathsBetween x x` is [ x ], whose endpoints
        # coincide, so no node lies strictly between them. `tail` leaves [ ] and `init [ ]`
        # refuses — a prelude list primitive naming neither the origin nor the query — so
        # the guard is what makes `interior` total on the paths `pathsBetween` actually
        # returns. It changes no other answer: every path of length ≥ 2 takes the same
        # `init (tail p)` it always did, and an empty interior cuts nothing, which is the
        # rule the origin already had ("changedId is NEVER an interior node").
        interior = p: if builtins.length p < 2 then [ ] else prelude.init (prelude.tail p);
        # A node cuts a path iff the overlay marks it true AND it is hashable: a
        # null-hash node is always-dirty and can NEVER be a cutoff (missing overlay
        # key reads false via `or false`).
        isCut = n: (cutoffs.${n} or false) && (ctx.trace.${n}.hash or null) != null;
        # Per-path witness: the first interior cut node, or null if the path is LIVE.
        cutWitness =
          p:
          let
            cuts = builtins.filter isCut (interior p);
          in
          if cuts == [ ] then null else builtins.head cuts;
        witnesses = map cutWitness paths;
        # Every path blocked ⇒ cutoff; cutNodes = the deduped sorted SET of witnesses
        # (one per blocked path — when different paths are cut by different nodes
        # there is no single common cutAt). A live path (null witness) ⇒ recomputed.
        allBlocked = builtins.all (w: w != null) witnesses;
        cutNodes = sort (prelude.unique (builtins.filter (w: w != null) witnesses));
      in
      if allBlocked then
        {
          verdict = "cutoff";
          inherit cutNodes paths;
        }
      else
        {
          verdict = "recomputed";
          inherit paths;
        };

  # why : BuiltCtx -> { id; changedId; cutoffs ? {} } -> WhyResult
  # The verdict fast path (canReach) answers unaffected/recomputed in
  # Θ( Σ_{u ∈ reach id} (1 + outdeg u) ) — reducing to the cone's size only at
  # BOUNDED out-degree — and carries NO paths key when `cutoffs == {}`;
  # paths/cutNodes are materialized only under a non-empty cutoff overlay (or
  # explain mode).
  why =
    ctx:
    {
      id,
      changedId,
      cutoffs ? { },
    }:
    # l∈C : `id` is in changedId's recompute cone iff it can reach changedId over
    # forward edges (or IS changedId — the change origin, always recomputed). No
    # transpose: canReach already walks consumer→producer.
    _verdict ctx { inherit changedId cutoffs; } (
      i: i == changedId || graph.canReach (graphView ctx.accessor) i changedId
    ) id;

  # whyFor : BuiltCtx -> { changedId; cutoffs ? {} } -> id -> WhyResult
  #
  # THE AMORTIZED DUAL OF `why`, CURRIED ON THE CHANGE. Membership in changedId's
  # recompute cone is loop-invariant across the ids of one change, exactly as a
  # traversal's per-visit edge wrapping is loop-invariant across the traversals of
  # one accessor — and it is resolved the same way the graph layer resolves that
  # one: a SEPARATE operator the caller binds once and spends, rather than a change
  # to the per-call form. A caller asking about one id must not be made to pay for a
  # whole reverse index, so `why` keeps its contract and the amortization stays a
  # decision the CALLER takes by reaching for this function.
  #
  # The cone is Arntzenius 2016 Datafun single-target reverse reachability (`dirtySet`
  # over `graph.dependentsOf`), so the bound is that operator's, paid ONCE per
  # `changedId` rather than once per id: Θ(n + E) to build the reverse index — it reads
  # EVERY node's out-edges, reachable or not — then a BFS over that index costing
  #   Θ( Σ_{u ∈ reach⁻ changedId} (1 + indeg u) )
  # → reducing to the cone's size only where in-degree is BOUNDED, and never falling
  # below the Θ(n + E) the index build pays whatever the cone's size. Membership is
  # then a lookup: the cone is INDEXED with genAttrs, never scanned as a list — a
  # closed-over list would trade a query per id for a scan per id.
  #
  # ONLY THE MEMBERSHIP DECISION IS AMORTIZED. Under a non-empty cutoff overlay the
  # verdict still enumerates paths per id through `graph.pathsBetween` (exponential
  # worst case), identically to `why`: the cone decides who is in the cone, never
  # which paths are cut. No claim is made here about the overlay path's cost.
  whyFor =
    ctx:
    {
      changedId,
      cutoffs ? { },
    }:
    let
      # Bound HERE — once per (ctx, changedId), whatever the caller spends it on.
      cone = prelude.genAttrs (dirtySet ctx [ changedId ]) (_: true);
    in
    _verdict ctx { inherit changedId cutoffs; } (i: cone ? ${i});

  # whyNot : the negative operator query — why `id` was NOT recomputed.
  #
  #   whyNot : BuiltCtx -> WhyArgs
  #          -> { reason :: "recomputed" | "cutoff" | "unaffected"; at :: [id] }
  #
  # THE SHAPE IS TOTAL, AND MAKING IT SO IS A CORRECTION rather than a carry. This
  # answered `null` for the recomputed case — an ABSENCE where every other verdict is
  # a record. That leaves the one answer meaning "nothing was avoided here" as the one
  # a caller cannot read a reason off, and indistinguishable from a query that returned
  # nothing at all. All three verdicts now carry the same two fields: `reason` names
  # the verdict and `at` carries the cut witnesses, `[ ]` where the verdict has none.
  # The empty list is the honest value for "no node cut this", not a default standing
  # in for an unasked question.
  # The verdict → reason mapping, defined ONCE: the dual below wraps the same
  # function, so the two negative queries cannot drift into two contracts.
  _reason =
    r:
    if r.verdict == "cutoff" then
      {
        reason = "cutoff";
        at = r.cutNodes;
      }
    else
      {
        reason = r.verdict;
        at = [ ];
      };

  whyNot = ctx: args: _reason (why ctx args);

  # whyNotFor : `whyFor`'s cone with `whyNot`'s record — the amortized dual of the
  # negative query, wrapping `whyFor` exactly as `whyNot` wraps `why`. A caller
  # looping the negative query has the same loop-invariant to hoist as one looping
  # the positive, and leaving it out would amortize half of a uniform surface.
  whyNotFor =
    ctx: args:
    let
      verdictFor = whyFor ctx args;
    in
    id: _reason (verdictFor id);
in
{
  inherit
    support
    supportDirect
    why
    whyFor
    whyNot
    whyNotFor
    ;
}
