# restabilize — per-member semi-naive SCC solver (runScc).
#
# Solves ONE strongly-connected component to its least fixed point by iterating
# each member's lattice from ⊥ (bottom) until per-member equality (quiescence).
# In-SCC deps read the CURRENT iterate; external (lower-stratum) deps read the
# fixed `store`/`higherStrata` — exactly what the merged `store // higherStrata
# // prev` provides to `recompute`.
#
# Theory citations:
#   - Arntzenius 2016 (Datafun Lemma 4): for a GENUINE-join (union/powerset, or
#     any finite-height bounded semilattice) lattice, iterate-from-⊥ ascends a
#     finite chain ⊥ ⊑ f(⊥) ⊑ f²(⊥) ⊑ … and converges at the lfp, detected by
#     eq-stabilization (prev == next). The reachability fixture is the ascent
#     witness: ⊥ = {} ⊑ {self} ⊑ {a,b}.
#   - Sloane 2010 §2.2 / Magnusson–Hedin (circular reference attributes): for an
#     OVERWRITE / no-op "join" (e.g. `join = _prev: v: v`) — which is NOT a
#     semilattice join, has no ⊑ order and no ascent witness — this is naive
#     iterate-to-stabilization: keep recomputing until the values stop moving.
#     Such fixtures converge by peer-agreement, NOT by lattice ascent.
#
# Honest gaps (load-bearing; consumer obligations, NOT checked here):
#   - MONOTONICITY of `recompute`/`join` is UNCHECKED. A non-monotone step can
#     oscillate forever (no Kleene/Arntzenius termination guarantee).
#   - FINITE HEIGHT of the lattice is UNCHECKED. An infinite-ascending chain
#     never quiesces.
#   - The ONLY divergence guard is per-member `maxIter`: on overrun, runScc
#     throws a LOCATED, tryEval-CATCHABLE blame (never Nix's uncatchable infinite
#     recursion). `widen` (applied after join, per-member) is the consumer's tool
#     to force finite ascent on tall/infinite lattices. ★ That guard is a
#     CONSUMER-DECLARED ITERATION BOUND, not a ceiling the ascent is known to
#     have: a lattice that would converge at maxIter + 1 is refused, and the
#     refusal names the still-moving members rather than claiming divergence.
#   - ★★ AND IT IS REQUIRED, WITH NO ENGINE-SUPPLIED DEFAULT. The bound is only
#     honest while it is the consumer's own assertion about their own lattice
#     ("mine converges within N, else refuse me"). A default would have the engine
#     assert a bound about a lattice it knows nothing about — neither monotonicity
#     nor height is checkable here — and then blame the consumer at a number the
#     consumer never supplied. An absent declaration is therefore a build error
#     naming the members that owe one, not a silent 100.
#   - This is OUTSIDE the rebuilder's acyclic envelope (build.nix prechecks
#     acyclicity and forbids cycles); runScc is the cyclic-stratum solver that
#     the acyclic build cannot express.
#
# `graph` is threaded for sibling ops (restabilize lands beside this); runScc
# itself takes its topology via the `accessor` field.
{ prelude, graph, ... }:
let
  inherit (import ./hash.nix { }) hashGuarded hashMoved;

  # runScc — solve one SCC to its least fixed point (per-member iterate-from-⊥).
  #
  # runScc :: {
  #   accessor,            # any object exposing .edges / .nodeData (topology oracle)
  #   store,               # externals map (lower-stratum / fixed inputs)
  #   recompute,           # accessor -> store -> id -> value (the node-eval)
  #   scc,                 # [id] — the SCC member ids (M)
  #   higherStrata,        # { <id> = value } — already-solved lower-stratum results
  #   lattices,            # per-NODE { bottom; join; maxIter; eq ? (==); widen ? null; }
  # } -> { <id> = value }   # the fixed-point iterate for each SCC member
  runScc =
    {
      accessor,
      store,
      recompute,
      scc,
      higherStrata,
      lattices,
    }:
    let
      M = scc;
      # Per-member equality, defaulting to structural `==` when the lattice omits eq.
      eqOf = m: lattices.${m}.eq or (a: b: a == b);

      # The declared iteration bound: the largest per-member maxIter in the component.
      # Every member must declare one — see the header. The members that do not are the
      # blame, by name, so the refusal is about the declaration and not about the ascent.
      undeclaredBound = prelude.filter (m: !(lattices.${m} ? maxIter)) M;
      undeclaredBoundBlame = {
        why = "undeclared-maxiter";
        nodes = undeclaredBound;
        scc = M;
      };
      maxI = prelude.foldl' (acc: m: prelude.max acc lattices.${m}.maxIter) 0 M;

      # One ascent step. In-SCC deps read the current iterate (prev); externals read
      # store / higherStrata. The // merge gives `recompute` the unified view.
      # PINNED DETAIL 1: widen applies AFTER join, per-member.
      ascend =
        prev:
        let
          cur = prelude.genAttrs M (m: recompute accessor (store // higherStrata // prev) m);
        in
        prelude.mapAttrs (
          m: _v:
          let
            j = lattices.${m}.join prev.${m} cur.${m};
          in
          if (lattices.${m}.widen or null) != null then lattices.${m}.widen prev.${m} j else j
        ) cur;

      # THE ASCENT IS A BOUNDED ITERATION, NOT A RECURSION, AND THAT IS LOAD-BEARING.
      #
      # A loop written as a self-applying lambda costs one evaluator frame per round —
      # Nix does not reuse the frame of a tail call — so its descent depth IS the round
      # count and past the call-depth limit it aborts UNCATCHABLY. `tryEval` does not
      # contain a stack overflow, so a recursive ascent loses precisely the catchable
      # blame the bound exists to raise: the guard would disappear at the depth it is
      # for. `iterateBounded` is `foldl'` — a C-level loop whose frame cost is constant
      # in the round count — and it forces the named loop-carried fields on every
      # intermediate state, because a field the control flow never reads chains
      # thunk-on-thunk across rounds and overflows the C stack instead, a second and
      # distinct uncatchable abort that no call-depth setting bounds. All three fields
      # are named below: forcing some of them measures the same as forcing none.
      #
      # The primitive applies `step` once per bound element and needs `step` to be the
      # IDENTITY once no work remains — which quiescence already is, so the surplus
      # rounds idle and the result is the fixed point a recursion would have reached.
      step =
        st:
        if st.settled then
          st
        else
          let
            next = ascend st.values;
          in
          {
            values = next;
            # Per-MEMBER eq: each node's OWN eq predicate drives its quiescence.
            settled = prelude.all (m: eqOf m st.values.${m} next.${m}) M;
            iters = st.iters + 1;
          };
      strict = st: builtins.seq st.values (builtins.seq st.settled st.iters);

      final = prelude.iterateBounded strict step {
        # Per-member ⊥ seed (Arntzenius iterate-from-bottom).
        values = prelude.genAttrs M (m: lattices.${m}.bottom);
        settled = false;
        iters = 0;
      } (prelude.range 1 maxI);

      # PINNED DETAIL 2: lastDelta = the still-moving members' prev/next pairs — the
      # step the bound refused to take, so the blame shows what was still moving.
      blame =
        let
          next = ascend final.values;
          moving = prelude.filter (m: !(eqOf m final.values.${m} next.${m})) M;
        in
        {
          why = "fixpoint-diverged";
          scc = M;
          inherit (final) iters;
          lastDelta = prelude.genAttrs moving (m: {
            prev = final.values.${m};
            next = next.${m};
          });
        };
    in
    # Bound-overrun blame: a tryEval-CATCHABLE thrown blame, never Nix infinite recursion.
    if undeclaredBound != [ ] then
      throw "gen-memo: cyclic member declares no maxIter: ${builtins.toJSON undeclaredBoundBlame}"
    else if final.settled then
      final.values
    else
      throw "gen-memo: fixpoint did not converge: ${builtins.toJSON blame}";

  # restabilize — the CYCLIC-CAPABLE analogue of `override`.
  #
  # `restabilize ctx changedId newDecls` replaces changedId's nodeData, then
  # re-solves ONLY the dependent cone of changedId — acyclic cone strata by
  # recompute-and-splice (== override), cyclic cone strata by `runScc` (per-SCC
  # least fixed point) — reading every non-cone node out of the prior store
  # (held fixed). Requires `ctx.fixpoint != null` (build with a fixpoint first).
  # Returns an updated cyclic-capable BuiltCtx: `accessor` is the NEW topology
  # and `fixpoint` is threaded forward UNCHANGED, so restabilize ∘ restabilize
  # stays cyclic-capable.
  #
  # SOUNDNESS (read precisely — restabilize makes NO optimality claim):
  #   - Non-cone node n: n ∉ dependentsOf(changedId) ⇒ n does not transitively
  #     read changedId ⇒ its value is unchanged from ctx.store, which equals a
  #     from-scratch build over accessor' (Acar 2002 §4.5/§7 change propagation:
  #     only the cone re-evaluates; change propagation "yields essentially the
  #     same result as a complete re-execution on the changed inputs"). So the
  #     fold is SEEDED at ctx.store and non-cone strata are simply skipped.
  #   - ACYCLIC cone node: recomputed reading already-solved lower strata as
  #     externals ⇒ BYTE-IDENTICAL to a full rebuild's value. This is exactly
  #     v1 `override`'s guarantee, retained in full.
  #   - CYCLIC cone SCC (whole-SCC, because mutual reachability ⇒ all-or-none in
  #     the cone): `runScc` ascends to its lfp on the SAME finite-height
  #     semilattices with the SAME externals as a from-scratch build over
  #     accessor'. On a finite-height bounded semilattice the lfp is UNIQUE
  #     (Arntzenius 2016 Datafun Lemma 4), so restabilize's incremental cyclic
  #     solve and the full build coincide: FIXED-POINT-EQUALITY. This is NOT the
  #     v1 byte-identical-to-the-acyclic-fix property — it is equality of two
  #     fixpoint computations to the same unique lfp.
  #   - Under a NON-MONOTONE recompute the only guarantee is runScc's per-member
  #     maxIter located blame (a catchable throw, never Nix infinite recursion).
  #
  # EXPLICITLY OUTSIDE RTD 1983's acyclic envelope: RTD requires noncircularity,
  # and BOTH its O(|AFFECTED|) optimality bound and its never-assign-a-
  # non-final-value invariant break on cycles. restabilize claims neither — its
  # cost is O(height · |SCC| · recompute) per cyclic stratum (Arntzenius-grounded
  # Kleene ascent), RTD-disclaimed. The AFFECTED post-filter below is reused only
  # as a trace-pruning convenience (re-hash the cone nodes that actually moved),
  # NOT as an optimality claim.
  restabilize =
    ctx: changedId: newDecls:
    let
      fixpoint = ctx.fixpoint or null;

      # accessor' : prior topology with changedId's nodeData replaced. Edges fall
      # through to ctx.accessor (unchanged) ⇒ same cyclic set, same condensation.
      accessor' = ctx.accessor // {
        nodeData = id: if id == changedId then newDecls else ctx.accessor.nodeData id;
      };

      # Relaxed precheck on the new topology (edges fixed ⇒ same cyclic set, but
      # computed fresh to mirror build). A cyclic node lacking a lattice is a
      # LOCATED blame — restabilize's own check (build would have rejected the
      # fixpoint up front, but a post-build mutation can drop one).
      cyclic = graph.cycles accessor';
      missing = builtins.filter (id: !(fixpoint.lattices ? ${id})) cyclic;
      undeclaredBlame = {
        why = "undeclared-cyclic-node";
        nodes = missing;
        cycle = cyclic;
      };

      cond = graph.condensation accessor';
      cyclicSet = prelude.genAttrs cyclic (_: true);

      # Dependent cone of changedId (reverse reachability; valid on cyclic
      # graphs — Arntzenius 2016 reverse reachability).
      cone = prelude.unique ([ changedId ] ++ graph.dependentsOf accessor' changedId);
      coneSet = prelude.genAttrs cone (_: true);

      # Bottom-up fold (producers-first over the condensation), accumulator SEEDED
      # at ctx.store: non-cone strata are skipped (their ctx.store values are
      # unaffected by a data change to changedId and stay), cone strata are
      # re-solved reading acc (already-solved lower strata) as externals.
      solved = prelude.foldl' (
        acc: tag:
        let
          members = cond.members.${tag} or [ ];
          coneMembers = builtins.filter (m: coneSet ? ${m}) members;
          isCyclicStratum = builtins.any (m: cyclicSet ? ${m}) members;
          next =
            if coneMembers == [ ] then
              # Stratum untouched by the cone: keep its ctx.store values verbatim.
              acc
            else if isCyclicStratum then
              # Whole SCC is in the cone (mutual reachability ⇒ all-or-none); re-solve
              # the component once to its lfp, reading acc (lower strata) as externals.
              acc
              // runScc {
                inherit recompute;
                accessor = accessor';
                store = { };
                scc = members;
                higherStrata = acc;
                lattices = fixpoint.lattices;
              }
            else
              # Acyclic cone singleton: recompute reading acc (lower strata) as
              # externals. Byte-identical to a full rebuild's value (== override).
              acc // prelude.genAttrs coneMembers (m: recompute accessor' acc m);
        in
        # The single loop-carried field, forced per stratum: every reader of `acc`
        # below it is lazy, so unforced the fold builds one `//` thunk per stratum and
        # the chain overflows the C stack when something forces it, uncatchably.
        builtins.seq next next
      ) ctx.store cond.bottomUp;

      store = solved;
      newHashOf = id: hashGuarded hashOf store.${id};
      # AFFECTED = the cone nodes whose hash actually moved (RTD §4.3 post-filter,
      # null-safe). Reused/unaffected cone nodes keep their prior trace entry.
      affected = builtins.filter (id: hashMoved (newHashOf id) (ctx.trace.${id}.hash or null)) cone;
      trace' =
        ctx.trace
        // prelude.genAttrs affected (id: {
          deps = accessor'.edges id;
          hash = newHashOf id;
        });

      # recompute / hashOf come from ctx; fixpoint is threaded forward unchanged.
      inherit (ctx) recompute hashOf;
    in
    if fixpoint == null then
      throw "gen-memo: restabilize requires ctx.fixpoint (build with a fixpoint param first)"
    else if missing != [ ] then
      throw "gen-memo: undeclared cyclic node: ${builtins.toJSON undeclaredBlame}"
    else
      {
        store = store;
        trace = trace';
        accessor = accessor';
        inherit recompute hashOf fixpoint;
      };
in
{
  inherit runScc restabilize;
}
