# build — full evaluation into a flat relocatable store + a verifying trace.
#
# The store is FLAT and RELOCATABLE — an id-keyed map of plain values rather than
# thunks closed over an evaluation — and that is THIS LIBRARY'S OWN claim about
# its own store. Mokhov 2018 §3.1 defines the Store and states neither property.
# What is Mokhov's here is §4.2.2's verifying trace (per-key `{ deps; hash }`) and
# §2.1/§4.1 acyclicity (cyclic deps not allowed ⇒ each task executed at most
# once). Dependency-order resolution is call-by-need — Nix's own laziness, not a
# scheduler of ours.
#
# ★★ AND BECAUSE IT IS NOT A SCHEDULER OF OURS, THE STORE IS POPULATED BY AN ENGINE
# HANDED IN, WHICH IS WHAT THE FIRST ARGUMENT IS FOR. Mokhov's decomposition splits a
# build system into a SCHEDULER, which orders the tasks and produces the store, and a
# REBUILDER, which decides whether a task must run at all. This library is the
# rebuilder half. A store-fix bound HERE — a self-referential store over the node set,
# passed into the caller's `recompute` — would make the plane produce values rather
# than decide about them, which is the one thing a decision layer may not do, and it
# would stand a second scheduler beside the evaluator's in a design whose premise is
# that Nix's laziness already is the scheduler. So `build` takes the engine and CALLS
# it, supplying the domain, the base and a decision, exactly as the warm fold takes
# `evalWarm` and calls that. A caller of an evaluator is not an evaluator.
#
# Consumes a gen-graph accessor (the topology oracle) and a caller-supplied
# `recompute` (the node-eval, `accessor -> store -> id -> value`). Pre-checks
# acyclicity via graph.cycles and throws a *located* blame on a cycle — catchable
# via builtins.tryEval, never Nix's uncatchable infinite recursion inside the
# scheduler's loop; the precheck is the rebuilder's, and the termination it buys is
# the scheduler's. Returns a BuiltCtx threading everything `override` needs to splice
# incrementally. The engine is NOT among the threaded fields — it is supplied at every
# entry and stored nowhere, so nothing the plane carries forward is an evaluator.
#
# Optional `fixpoint` param (default null): when null, build is exactly the
# acyclic behaviour above — throw-on-any-cycle, one scheduled store, no `fixpoint`
# key in the returned ctx. When present, build relaxes the precheck (a cycle is
# allowed iff every cyclic node carries a declared lattice) and computes the
# store STRATIFIED bottom-up over the condensation (quotient) graph:
#   - SCC partition + condensation: Tarjan 1972 / Kosaraju quotient-graph idiom,
#     READ through gen-graph's one published partition door. The plane consumes a
#     partition; it does not compute one, and its default arm is that door's.
#   - Per cyclic stratum: Arntzenius 2016 (Datafun Lemma 4) per-SCC least fixed
#     point via `runScc` (iterate-from-⊥ on the member lattices to quiescence).
#   - `cond.bottomUp` is PRODUCERS-FIRST (a consumer SCC appears after every SCC
#     it depends on), so each stratum reads already-CONVERGED lower strata out of
#     the accumulator. This is the build-domain-restriction: solve over the
#     ascending prefix only. It is what AVOIDS the bare-splice divergence — a
#     single scheduled store over all nodes dispatching `id ∈ scc ?
#     runScc : recompute` re-invokes runScc once per MEMBER and can read a
#     not-yet-converged peer SCC, a self-referential thunk black-hole that
#     escapes builtins.tryEval (Nix uncatchable infinite recursion). The
#     bottom-up fold never forms that thunk: a stratum is only ever solved once,
#     after its producers.
#
# Honest gap: the fixpoint path is OUTSIDE Mokhov/RTD's acyclic envelope. Each
# per-SCC convergence rests on the consumer's UNCHECKED monotonicity + finite-
# height obligation (Arntzenius's preconditions for Kleene ascent); the only
# runtime divergence guard is `runScc`'s per-member maxIter (a catchable blame).
#
# Edge convention: accessor.edges id = [ids that id depends on] (consumer→producer).
{ prelude, graph, ... }:
let
  inherit (import ./hash.nix { }) hashGuarded;
  inherit (import ./restabilize.nix { inherit prelude graph; }) runScc;

  build =
    engine:
    {
      accessor,
      recompute,
      hashOf,
      fixpoint ? null,
    }:
    let
      # Authoritative cyclic id-set (sorted) — graph.cycles (gen-graph/lib/global.nix).
      cyclic = graph.cycles accessor;

      # Per-key trace shape, shared by both paths (Mokhov verifying-trace shape):
      # per-key dep list + content hash (null when the value is unhashable).
      traceFor =
        store:
        prelude.genAttrs accessor.nodes (id: {
          deps = accessor.edges id;
          hash = hashGuarded hashOf store.${id};
        });

      # --- acyclic path: throw-on-any-cycle, one scheduled store. ----------------
      acyclic =
        let
          # Located cycle blame: throw-on-any-cycle (Mokhov 2018 §2.1/§4.1, cyclic
          # deps not allowed). gen-graph supplies the ids; the blame record is ours.
          blame =
            let
              a = builtins.head cyclic;
              b = if builtins.length cyclic > 1 then builtins.elemAt cyclic 1 else a;
            in
            {
              why = "cycle";
              cycle = cyclic;
              path = graph.pathsBetween accessor a b;
            };

          # The flat relocatable store (this library's own property, see the header).
          # The DECISION is `nothing is clean` — a cold build consults no prior, which is
          # the same thing the byte-parity oracle means by its cold arm — so `base` is
          # empty and every node is recomputed. The engine resolves deps in dependency
          # order by call-by-need; it terminates because the precheck above guarantees
          # acyclicity.
          store = engine.schedule {
            inherit accessor recompute;
            domain = accessor.nodes;
            base = { };
            isClean = _: false;
          };
          trace = traceFor store;
        in
        if cyclic != [ ] then
          throw "gen-memo: cycle detected: ${builtins.toJSON blame}"
        else
          {
            inherit
              store
              trace
              accessor
              recompute
              hashOf
              ;
          };

      # --- fixpoint path: condensation-stratified bottom-up solve. ---------------
      stratified =
        let
          # Relaxed precheck: a cycle is allowed iff every cyclic node carries a
          # declared lattice. The undeclared ones are the blame (both fields kept
          # for debugging: `nodes` = the cyclic nodes lacking a lattice, `cycle` =
          # the full authoritative cyclic set).
          missing = builtins.filter (id: !(fixpoint.lattices ? ${id})) cyclic;
          undeclaredBlame = {
            why = "undeclared-cyclic-node";
            nodes = missing;
            cycle = cyclic;
          };

          # The partition arrives through gen-graph's one published front door. The plane
          # READS a partition and never builds one: reverse reachability and the quotient
          # by mutual reachability are that library's concern, and a second partitioner
          # here would be a second answer to a question one library already owns. The
          # door's record is PLAIN DATA — `members` is a map, not a lookup function,
          # because a function's identity is minted by the build that made it and cannot
          # cross a library boundary.
          cond = graph.condensation accessor;
          cyclicSet = prelude.genAttrs cyclic (_: true);

          # Bottom-up fold over the condensation strata (producers-first). Each
          # stratum reads the accumulator `acc` (the already-converged lower
          # strata) as its externals.
          solved = prelude.foldl' (
            acc: tag:
            let
              members = cond.members.${tag} or [ ];
              isCyclicStratum = builtins.any (m: cyclicSet ? ${m}) members;
              next =
                if isCyclicStratum then
                  # Cyclic SCC: solve to its lfp ONCE for the whole component
                  # (Arntzenius per-SCC fixpoint). Lower strata already sit in acc.
                  acc
                  // runScc {
                    inherit accessor recompute;
                    store = { };
                    scc = members;
                    higherStrata = acc;
                    lattices = fixpoint.lattices;
                  }
                else
                  # Acyclic singleton: recompute reading acc (lower strata) as
                  # externals. Byte-identical to the acyclic path's scheduled value
                  # (deps already in acc, walked in dependency order).
                  #
                  # ★ THIS STRATUM FOLD IS NOT ROUTED THROUGH THE ENGINE, and the
                  # residue is named rather than left to be noticed: it threads its own
                  # accumulator of resolved outputs across a traversal it drives, which
                  # is the same thing a store-fix is by a different construction. The
                  # bottom-up solve over the condensation, and `runScc` beneath it, are
                  # the cyclic half's outstanding re-expression.
                  acc // prelude.genAttrs members (m: recompute accessor acc m);
            in
            # The single loop-carried field, forced per stratum. Every reader of `acc`
            # below is lazy — `higherStrata` and `recompute`'s store argument both — so
            # left unforced the fold builds one `//` thunk per stratum and the chain
            # overflows the C stack when something finally forces it, uncatchably.
            builtins.seq next next
          ) { } cond.bottomUp;

          store = solved;
          trace = traceFor store;
        in
        if missing != [ ] then
          throw "gen-memo: undeclared cyclic node: ${builtins.toJSON undeclaredBlame}"
        else
          {
            inherit
              store
              trace
              accessor
              recompute
              hashOf
              fixpoint
              ;
          };
    in
    if fixpoint == null then acyclic else stratified;
in
{
  inherit build;
}
