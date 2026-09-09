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
  inherit (import ./graph-view.nix { }) graphView;

  # runScc — solve one SCC to its least fixed point (per-member iterate-from-⊥).
  #
  # runScc :: ascend -> {
  #   accessor,            # any object exposing .dependencies / .nodeData (topology oracle)
  #   store,               # externals map (lower-stratum / fixed inputs)
  #   recompute,           # accessor -> store -> id -> value (the node-eval)
  #   scc,                 # [id] — the SCC member ids (M)
  #   higherStrata,        # { <id> = value } — already-solved lower-stratum results
  #   lattices,            # per-NODE { bottom; join; maxIter; widen ? null; }
  # } -> { <id> = value }   # the fixed-point iterate for each SCC member
  #
  # ★ THE LOOP IS THE EVALUATOR'S AND ARRIVES HANDED IN, WHICH IS THE SAME SEAM `restabilize` BELOW
  # TAKES ITS ENGINE THROUGH. `ascend` is gen-scope's content-free bounded-ascent driver: it carries
  # the seed, the round counter, the per-member settlement quantifier and the per-round forcing, and
  # it knows nothing about a lattice. Everything lattice-shaped stays on THIS side — the merged view,
  # `join`, `widen`, the declared bound, and every refusal below — because the driver holds no
  # refusals and a located blame needs to know what a member is.
  #
  # ★ NO PER-MEMBER `eq`. den-hoag-k2p6 OQ-1 (owner-ruled 2026-09-09): gen-scope's closeCycle keeps
  # its quotient ruling — a coarse-equality carrier is not driven in a shared round — so a per-member
  # equality predicate published here is content the ruled engine will never honour. Quiescence is
  # structural `==` for EVERY member; a lattice record still carrying `eq` is refused by name below,
  # not silently accepted (ADR-0008 item 2: this plane decides reuse and never evaluates).
  #
  # It is CURRIED rather than taken as a module argument, and the reason is scope: `build.nix` binds
  # this function in a top-level `let`, outside the `engine:` lambda, so `engine.ascend` is not
  # visible where the binding is made. Both call sites sit inside that lambda and apply it there.
  runScc =
    ascend:
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
      # Quiescence is structural `==` for every member — the retired `eq` term's only surviving
      # value (den-hoag-m6y9p / den-hoag-k2p6 OQ-1).
      structEq = a: b: a == b;

      # A lattice record that still carries the retired `eq` key is refused BY NAME (member id +
      # the offending key), never silently ignored.
      eqKeyed = prelude.filter (m: lattices.${m} ? eq) M;
      eqKeyedBlame = {
        why = "retired-eq-key";
        key = "eq";
        nodes = eqKeyed;
        scc = M;
      };

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

      # One ascent step — the whole round, which is what the driver takes as `advance`. In-SCC deps
      # read the current iterate (prev); externals read store / higherStrata. The // merge gives
      # `recompute` the unified view.
      # PINNED DETAIL 1: widen applies AFTER join, per-member.
      advance =
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

      # THE ASCENT IS A BOUNDED ITERATION, NOT A RECURSION, AND THAT IS LOAD-BEARING — but the
      # encoding is no longer written here. A loop written as a self-applying lambda costs one
      # evaluator frame per round (Nix does not reuse the frame of a tail call), so its descent depth
      # IS the round count and past the call-depth limit it aborts UNCATCHABLY: `tryEval` does not
      # contain a stack overflow, so a recursive ascent would lose precisely the catchable blame the
      # bound below exists to raise. The driver settles that by folding — `prelude.iterateBounded`,
      # whose frame cost is constant in the round count — and it forces the loop-carried fields on
      # every intermediate state, because a field the control flow never reads chains thunk-on-thunk
      # across rounds and overflows the C stack instead, a second and distinct uncatchable abort. The
      # hand-written `strict` that used to name three fields here is GONE rather than relocated: the
      # forcing is derived from the accumulator's own fields on the driver's side, so a field added
      # later is forced without anyone re-applying the discipline.
      #
      # WHAT THIS SIDE STILL OWES, because the driver claims neither: that the ascent reaches a fixed
      # point at all (Arntzenius's monotonicity and finite height — unchecked, per the header), and
      # that `maxI` is long enough to get there. The refusals below are where the second one is
      # answered, and they are answered by name.
      final = ascend {
        members = M;
        # Per-member ⊥ seed (Arntzenius iterate-from-bottom).
        bottomOf = m: lattices.${m}.bottom;
        inherit advance;
        # Structural `==` for every member. `settledBy` IS the driver's
        # `member -> prev -> next -> bool`; the member argument goes unused.
        settledBy = _m: structEq;
        bound = prelude.range 1 maxI;
      };

      # PINNED DETAIL 2: lastDelta = the still-moving members' prev/next pairs — the
      # step the bound refused to take, so the blame shows what was still moving.
      blame =
        let
          next = advance final.values;
          moving = prelude.filter (m: !(structEq final.values.${m} next.${m})) M;
        in
        {
          why = "fixpoint-diverged";
          scc = M;
          # The driver counts `rounds`; the blame has always published `iters` and the name is part
          # of the message consumers match on, so it is renamed here rather than in the driver.
          iters = final.rounds;
          lastDelta = prelude.genAttrs moving (m: {
            prev = final.values.${m};
            next = next.${m};
          });
        };
    in
    # Refused-by-name blames are tryEval-CATCHABLE thrown blames, never Nix infinite recursion.
    if eqKeyed != [ ] then
      throw "gen-memo: cyclic member declares retired lattice key: ${builtins.toJSON eqKeyedBlame}"
    else if undeclaredBound != [ ] then
      throw "gen-memo: cyclic member declares no maxIter: ${builtins.toJSON undeclaredBoundBlame}"
    else if final.settled then
      final.values
    else
      throw "gen-memo: fixpoint did not converge: ${builtins.toJSON blame}";

  # restabilize — the CYCLIC-CAPABLE analogue of `override`.
  #
  # `restabilize engine ctx changedId newDecls` replaces changedId's nodeData, then
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
  #
  # WHAT "claims neither" DOES NOT DISCLAIM (den-hoag-xyme): RTD's invariant is
  # its OWN optimality-envelope property, stated in RTD's terms and abandoned
  # along with the O(|AFFECTED|) bound it travels with. It is not this plane's
  # never-serve-a-non-final-value discipline (Söderberg-Hedin 2013 §4.2's second
  # NTA obligation), which is not RTD's to disclaim in the first place — it is
  # ADR-0008 item 2's own definition of this plane (byte-/fixpoint-parity against
  # a cold evaluation). That discipline holds here BY CONSTRUCTION: `runScc`
  # below never returns and nothing is ever bound to `builtStore`/the returned
  # ctx before `settled` — an unconverged iterate is a local loop variable that
  # is discarded on ascent, never a value this function can cache or hand back.
  restabilize =
    engine: ctx: changedId: newDecls:
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
      cyclic = graph.cycles (graphView accessor');
      missing = builtins.filter (id: !(fixpoint.lattices ? ${id})) cyclic;
      undeclaredBlame = {
        why = "undeclared-cyclic-node";
        nodes = missing;
        cycle = cyclic;
      };

      cond = graph.condensation (graphView accessor');
      cyclicSet = prelude.genAttrs cyclic (_: true);

      # Dependent cone of changedId (reverse reachability; valid on cyclic
      # graphs — Arntzenius 2016 reverse reachability).
      cone = prelude.unique ([ changedId ] ++ graph.dependentsOf (graphView accessor') changedId);
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
              # The ascent loop is the ENGINE's, handed in here exactly as `schedule` is
              # below.
              acc
              // runScc engine.ascend {
                inherit recompute;
                accessor = accessor';
                store = { };
                scc = members;
                higherStrata = acc;
                lattices = fixpoint.lattices;
              }
            else
              # Acyclic cone singleton: scheduled by the engine, reading acc (lower
              # strata) as base. Byte-identical to a full rebuild's value (== override).
              # `schedule` returns the DOMAIN's keys alone, so the accumulator merge
              # stays explicit; an acyclic stratum is a singleton, so the engine's fix
              # has nothing to close over.
              acc
              // engine.schedule {
                accessor = accessor';
                inherit recompute;
                domain = coneMembers;
                base = acc;
                isClean = _: false;
              };
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
          deps = accessor'.dependencies id;
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
