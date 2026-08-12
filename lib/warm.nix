# warm — the override cone as a reuse DECISION, and the fold that carries it to an evaluator.
#
# THE EVALUATOR IS HANDED IN, NEVER TAKEN AS A DEPENDENCY. The fold receives `evalWarm` as an
# argument and calls it; this library declares no evaluator input, because the plane decides for an
# evaluator it is given and taking one as a dependency would invert the direction the whole design
# rests on. What the fold does with it is CALL it — assemble the edited roots, a decision and a
# prior, and let the evaluator produce every value. A caller of an evaluator is not an evaluator: it
# binds no self-referential store of its own and produces no node value by applying a caller's
# computation. The evaluator handed in is the sole recompute engine.
#
# THE DECISION IS THE INTERFACE, AND IT IS EXPORTED APART FROM THE FOLD. `warmDecision` is the whole
# of what this plane contributes to a warm evaluation: two total functions, `isClean` and
# `reusable`, and no values. The fold is decide-then-call on top of it, so a caller that wants only
# the decision takes only the decision, and the record that crosses the boundary has nowhere to put
# a result even if it wanted one.
#
# `isClean` IS THE COMPLEMENT OF THE DIRTY CONE, AND THE CONE IS READ RATHER THAN COMPUTED. The
# edited ids together with their reverse-reachable dependents are `dirtySet`, which reads
# `graph.dependentsOf`; every other node is clean. Reps–Teitelbaum–Demers 1983 §4.3: that is a SOUND
# OVER-APPROXIMATION of AFFECTED and not AFFECTED itself — the paper states of its own set that
# "AFFECTED is determined as a result of the updating process itself" — so the cone is always
# correct to recompute and is never minimal. The hash post-filter that narrows it is `affectedSet`.
# Narrowing the WARM cone the same way is not merely unimplemented, it is a bad trade inside one
# evaluation: detecting unchanged values would force (hash) the dominant per-host spine, and the
# evaluator would then force it again — the dominant cost paid twice to save part of it once. The
# exact-AFFECTED cutoff pays off across evaluations, and reuse across evaluations is not built.
#
# `reusable` IS THE EVALUATOR'S OWN VOCABULARY, READ OFF THE FACADE. What may be served warm is the
# resolutional projection the evaluator publishes — its attribute names minus the structural
# partition — and this plane neither recomputes that partition nor keeps a second answer to it. The
# filter that stood here decided warm-servability from a DECLARED stratum, one library away, on the
# author's say-so; a derived classifier answers the same question and therefore governs, since the
# burden of proof falls on the declaration and no argument that derivation is impossible can be
# given when the derivation is sitting on the accessor. What survives that supersession is the
# SIGNATURE — node in, attribute names out — which is `Decision.reusable`'s own shape.
#
# AND THE COST OF THE WIDER PARTITION, ON THE RECORD, because the note this replaces stated it at
# the narrow reading. The superseded filter excused itself with "children and derived-children are
# never warm-served anyway", which was true of two literal names. The partition the evaluator
# applies is wider — the whole `edges-*` family and `includes` as well — so a warm evaluation pays
# edge-set recomputation it did not pay before. That is a cost fact and not a correctness fact, and
# it is taken deliberately: an edge set IS the labelled reachability relation, and the reason
# structure is always recomputed applies to it exactly.
#
# THE SPLICE IS THIS LIBRARY'S OWN CONSTRUCTION AND CARRIES NO ATTRIBUTION. The content that arrived
# here credited a reverse-topological splice to Acar 2002; `topolog` occurs 0 times in that paper's
# archived extraction, against a live control of `adaptiv` ⇒ 76 in the same run. What is genuinely
# Acar's — the change/propagate split — lives in `drivers.nix` and is cited there.
{ prelude, graph, ... }:
let
  inherit (import ./dirtySet.nix { inherit prelude graph; }) dirtySet;
  inherit (import ./build.nix { inherit prelude graph; }) build;

  # The declaration keys whose presence in an edit moves an EDGE rather than a value. The fold below
  # decides reuse from a cone read over the topology as it stands; an edit that reshapes the graph
  # invalidates the cone that authorised the decision, so it is refused by name rather than served a
  # decision computed against a topology that no longer holds. Topology change is `structural.nix`'s
  # concern — `applyEdgeDelta` and `retract` — over the store ctx those operate on.
  edgeKeys = [
    "includes"
    "neededBy"
    "__edges"
    "parent"
  ];
  changesTopology = newDecls: builtins.any (k: newDecls ? ${k}) edgeKeys;

  # The projection over a prior evaluation, performed FROM THE ACCESSOR on demand. It is not an
  # artefact this plane constructs and carries: every value in it is fetched through the facade at
  # the moment it is read, so there is no second place where results live.
  priorProjection =
    prior: id:
    builtins.listToAttrs (
      map (a: {
        name = a;
        value = prior.get id a;
      }) (prior.resolutional id)
    );

  warmDecision =
    { accessor, prior }:
    seeds:
    let
      # Set rather than list: membership is asked once per node per attribute.
      dirty = prelude.genAttrs (dirtySet { inherit accessor; } seeds) (_: true);
    in
    {
      isClean = nid: !(dirty ? ${nid});
      reusable = prior.resolutional;
    };

  # Splice a set of data-change edits into the roots, mark the union of their reverse cones dirty,
  # and hand the evaluator ONE warm pass. Batching is not an optimisation bolted onto the single
  # case: the union of the cones is a single cone, so N edits cost one decision and one evaluation.
  warmSplice =
    { evalWarm }:
    ctx: edits:
    assert
      (builtins.all (id: builtins.hasAttr id ctx.roots) (builtins.attrNames edits))
      || throw "gen-memo.warm: edit target(s) must be root nodes — ${
        builtins.toJSON (builtins.filter (id: !(builtins.hasAttr id ctx.roots)) (builtins.attrNames edits))
      } not in roots (a node spawned during evaluation is not editable; edit the root that spawns it).";
    let
      ids = builtins.attrNames edits;
      roots' = builtins.foldl' (
        r: id:
        r
        // {
          ${id} = r.${id} // {
            decls = (r.${id}.decls or { }) // edits.${id};
          };
        }
      ) ctx.roots ids;
      accessor' = ctx.accessor // {
        nodeData = nid: (roots'.${nid} or { decls = { }; }).decls;
      };

      # The prior is the same evaluation's own restricted facade — `get`, `nodeIds`,
      # `resolutional` and nothing else. Nothing is materialised and handed forward, and nothing
      # persists past this evaluation: what is reused is a result held live in the evaluation the
      # caller is already inside.
      prior = ctx.eval.facade;
      decision = warmDecision {
        inherit prior;
        accessor = accessor';
      } ids;

      eval' = evalWarm {
        roots = roots';
        inherit (ctx) attributes parseParent;
        inherit prior decision;
      };

      # The verifying-trace shape (Mokhov 2018 §4.2.2): per key, its deps and a content hash. The
      # deps are the accessor's own declared edges, read where they live rather than through a
      # second surface that restates them. The hash is null, which this library's guards read as
      # conservatively-always-dirty — the same trade the cone makes, for the same reason: a hash
      # here would force the spine the evaluator is about to force anyway.
      trace' = prelude.genAttrs (builtins.attrNames eval'.allNodes) (nid: {
        deps = accessor'.edges nid;
        hash = null;
      });

      # A memo ctx over the warm evaluation, LAZY and forced by nothing on this path. Its recompute
      # reads its own paired evaluation, so its hashes describe that evaluation and no other. It is
      # the hook a reuse layer ACROSS evaluations would enter through, and that layer is a recorded
      # growth path rather than shipped scope: taking it means handing the plane a prior it did not
      # produce, which no instrument here can tell from a matching one, and it may not be taken
      # until one exists.
      builtCtx' = build {
        accessor = accessor';
        recompute =
          _acc: _store: nid:
          priorProjection eval'.facade nid;
        hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);
      };
    in
    ctx
    // {
      roots = roots';
      eval = eval';
      accessor = accessor';
      builtCtx = builtCtx';
      trace = trace';
    };
in
{
  inherit warmDecision;

  warmOverride =
    engine: ctx:
    { id, newDecls }:
    assert
      !(changesTopology newDecls)
      || throw "gen-memo.warmOverride: edge-move on '${id}' — this fold decides reuse from a cone read over the current topology and cannot serve an edit that reshapes it; topology change is applyEdgeDelta's.";
    warmSplice engine ctx { ${id} = newDecls; };

  # The batch form. One guard per edit, one union cone, one evaluation — `warmSplice` already
  # unions the cones, so this is a guard-and-delegate wrapper and not a second fold. It takes the
  # edits themselves rather than a list of changed ids: a pure batch has to carry the data-change
  # payload, and a bare id list cannot.
  warmResolve =
    engine: ctx:
    { edits }:
    assert
      builtins.all (id: !(changesTopology edits.${id})) (builtins.attrNames edits)
      || throw "gen-memo.warmResolve: edge-move in batch — this fold decides reuse from a cone read over the current topology and cannot serve an edit that reshapes it; topology change is applyEdgeDelta's.";
    warmSplice engine ctx edits;
}
