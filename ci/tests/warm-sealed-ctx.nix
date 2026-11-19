# THE PLANE, RUN AGAINST THE CTX THE PRODUCTION ASSEMBLER ACTUALLY SEALS.
#
# Every other warm suite here assembles its `ctx` by hand. That is the right shape for them — they
# hold the cone and the decision still, which is what those cells are about — but it leaves one
# thing unmeasured, and it is the thing that went wrong: a hand-assembled fixture agrees with the
# library because the same author wrote both, so the suite can be green against a record shape that
# NOTHING produces. That is exactly how the gap this suite exists for stayed invisible.
#
# WHAT WENT WRONG, ON THE RECORD, because the shape of the fix is only defensible against it.
# `gen-scope`'s `foldEquations` is the sole production assembler of the ctx this plane consumes. It
# sealed the node map as `roots` and did not seal the scope RECORD at all — so the declared vertex
# order and the kind registry stopped at the entry, and the warm fold, which must hand a record to
# `evalWarm`, could not be written against the real seal no matter what it read. The hand fixtures
# could not see it: they supplied whatever the library asked for.
#
# ⇒ THIS SUITE TAKES ITS CTX FROM `foldEquations` AND NOWHERE ELSE. Nothing here constructs a ctx
# field. If the seal stops publishing something the plane reads, these cells fail at evaluation,
# which is the signal the hand fixtures structurally cannot give.
#
# The schedule is a fixture record rather than a scheduler's output, for the reason gen-scope's own
# fold suite states: the entry reads exactly one field off it and forces the value itself, so a
# fixture carrying that field exercises everything the entry does with a schedule. What validated
# the grammar is the scheduler's concern and is asserted where the scheduler lives.
{
  graph,
  prelude,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride;

  hostKinds = genScope.mkKinds [ (genScope.mkKind { } "host") ];

  # `consumer` reads `producer` across a declared edge, so the cone has somewhere to reach and the
  # parity claim below is not a claim about one isolated node.
  mkScope =
    v:
    genScope.buildRoots {
      kinds = hostKinds;
      decls = {
        producer.v = v;
        consumer = { };
      };
      types = {
        producer = "host";
        consumer = "host";
      };
    };

  equations = {
    # ★ `children` IS DECLARED, NOT OMITTED (den-hoag-6imt). gen-scope refuses a descent from an
    # evaluation that declares no containment relation rather than answering `{ }` and reporting a
    # partial tree. `mkScope` declares no `parentGraph`, so both nodes are roots and `{ }` is the
    # true answer; the shape is `fold-equations.nix`'s own `children` equation, an `nta` on the
    # structural stratum.
    children = {
      name = "children";
      kind = "nta";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _self: _id: { };
    };
    imports = {
      name = "imports";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _self: _id: [ ];
    };
    p-val = {
      name = "p-val";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "resolution";
      compute = self: id: (self.node id).decls.v or 0;
    };
    sees = {
      name = "sees";
      kind = "synthesized";
      readsAttrs = [ "p-val" ];
      stratum = "resolution";
      compute = self: id: if id == "consumer" then (self.get "producer" "p-val") + 100 else 0;
    };
  };
  schedule = { inherit equations; };

  # The declared relation must over-declare the cross-node read for the cone to be sound — the same
  # contract `warm-override-cross-node.nix` states, here supplied to the real entry.
  #
  # ★ IT IS A CONTRACTED RELATION, NOT A LAMBDA (den-hoag-6imt, the same un-migrated-consumer class
  # as `children` above). `foldEquations` refuses a bare function by name — "must be the relation
  # `gen-graph.mkDeclaredEdges` returns; received a lambda" — because a value it cannot tell apart
  # from a contracted one is one it must refuse. The map below is the index the constructor
  # normalizes, and the membership authority is the scope's own node map, so the edge goes THROUGH
  # registration rather than around it. Shape taken from `gen-scope/ci/tests/_fixtures/declared.nix`.
  contractedFor =
    scope: rel:
    graph.mkDeclaredEdges (
      builtins.mapAttrs (_: ids: map (graph.mkNodeRef (id: scope.nodes ? ${id})) ids) rel
    );

  sealed =
    v:
    let
      scope = mkScope v;
    in
    genScope.foldEquations { } {
      inherit scope schedule;
      declaredDependencies = contractedFor scope { consumer = [ "producer" ]; };
      parseParent = _: null;
    };

  cold = sealed 1;
  warmed = warmOverride engine cold "producer" {
    v = 9;
  };
  fresh = sealed 9;

  probe =
    ctx: id: attr:
    ctx.eval.get id attr;

  # ── THE RETURNED RELATION: a fixture whose edits move it ──
  # The ctx a warm pass returns is a plane output, so its accessor (nodes, dependencies, the guarded
  # trace lookup) must be what a fresh `foldEquations` of the edited data publishes. The fixture
  # above moves no edge, so it cannot tell a returned relation from the prior's. This one moves
  # membership and selection:
  #   `h` (kind `fan`) grows one `nta` child per key of its `defs`;
  #   `s` (kind `sp`) spawns `s-<k>` per entry of its `kids`;
  #   `p` selects its registered children `k1` / `k2` by its `kids`;
  #   `z` declares `h`, `s` and `p`.
  # "refused" is a read that fails under `tryEval` after a deep force.
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "refused";
  addr = def: at: {
    attr = "defs";
    inherit def at;
  };
  ntaOf =
    key:
    genScope.mintNtaId {
      host = "h";
      name = "x";
      group = "g";
      inherit key;
    };
  fan =
    self: id:
    let
      d = builtins.head (self.get id "defs");
    in
    {
      g = if builtins.isAttrs d then builtins.mapAttrs (k: _: [ (addr 0 [ k ]) ]) d else { };
    };
  spawnKids =
    h: id:
    builtins.listToAttrs (
      map (k: {
        name = "${id}-${k}";
        value = {
          id = "${id}-${k}";
          decls.v = 1;
        };
      }) ((h.node id).decls.kids or [ ])
    );
  relKinds = genScope.mkKinds [
    (genScope.mkKind { } "plain")
    (genScope.mkKind { nta.x = fan; } "fan")
    (genScope.mkKind {
      below = [ "plain" ];
      spawns.plain = spawnKids;
    } "sp")
  ];
  relScopeAt =
    e:
    genScope.buildRoots {
      kinds = relKinds;
      types = {
        h = "fan";
        s = "sp";
        p = "plain";
        k1 = "plain";
        k2 = "plain";
        z = "plain";
      };
      decls = {
        h.defs = [
          {
            a = 1;
            b = 2;
          }
        ];
        s.kids = [ "a" ];
        p.kids = [ "k1" ];
        k1.v = 1;
        k2.v = 2;
        z.v = 0;
      }
      // e;
      parentGraph = genScope.overlays (
        map genScope.edge [
          {
            from = "k1";
            to = "p";
          }
          {
            from = "k2";
            to = "p";
          }
        ]
      );
    };
  relParent =
    id:
    let
      d = genScope.decodeNta id;
    in
    if d != null then
      d.host
    else if id == "k1" || id == "k2" then
      "p"
    else if builtins.match "s-(.*)" id != null then
      "s"
    else
      null;
  res = name: compute: {
    inherit name compute;
    kind = "synthesized";
    readsAttrs = [ ];
    stratum = "resolution";
  };
  relEquations = tag: {
    children = {
      name = "children";
      kind = "nta";
      readsAttrs = [ ];
      stratum = "structural";
      compute =
        self: id:
        if id == "p" then
          builtins.listToAttrs (
            map (k: {
              name = k;
              value = {
                id = k;
              };
            }) (self.node id).decls.kids
          )
        else
          { };
    };
    imports = {
      name = "imports";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _: _: [ ];
    };
    defs = res "defs" (
      self: id:
      let
        d = (self.node id).decls;
      in
      if d ? seed then map (e: e.value) d.seed else d.defs or [ ]
    );
    v = res "v" (self: id: (self.node id).decls.v or 0);
    # The prior program tags "prior", the current one "program": a value served from the prior
    # answers the first.
    tag = res "tag" (_: _: tag);
  };
  relDeclared = graph.mkDeclaredEdges {
    z = map (graph.mkNodeRef (_: true)) [
      "h"
      "s"
      "p"
    ];
  };
  relFoldWith =
    tag: e:
    genScope.foldEquations { } {
      scope = relScopeAt e;
      schedule.equations = relEquations tag;
      declaredDependencies = relDeclared;
      parseParent = relParent;
    };
  relFold = relFoldWith "program";
  relCold = relFold { };
  # One warm pass per edit, through the plane, from the ctx it is handed.
  relWarm =
    c: e:
    let
      id = builtins.head (builtins.attrNames e);
    in
    warmOverride engine c id e.${id};
  relChain = builtins.foldl' relWarm relCold;
  relMerged = es: relFold (builtins.foldl' (a: e: a // e) { } es);
  edits = {
    ES.s.kids = [
      "a"
      "b"
    ]; # a spawn grows `s-b`
    ESback.s.kids = [ "a" ]; # and shrinks back
    EX.h.defs = [ { a = 1; } ]; # an `nta` child goes
    EN.h.defs = [
      {
        a = 1;
        b = 2;
        c = 3;
      }
    ]; # an `nta` child arrives
    EP.p.kids = [
      "k1"
      "k2"
    ]; # the selection moves; the node set is held
    EZ.k2.v = 9; # an edit nothing else reads
  };
  probeIds = [
    "h"
    "s"
    "p"
    "k1"
    "k2"
    "z"
    (ntaOf "a")
    (ntaOf "b")
    (ntaOf "c")
    "s-a"
    "s-b"
  ];
  # The accessor as a consumer reads it, field by field and per id.
  fingerprint = ctx: {
    nodes = try ctx.accessor.nodes;
    deps = prelude.genAttrs probeIds (i: try (ctx.accessor.dependencies i));
    traceAt = prelude.genAttrs probeIds (i: try (ctx.accessor.trace i));
    trace = try ctx.trace;
    roots = try (builtins.attrNames ctx.roots);
    nodeData = prelude.genAttrs probeIds (i: try (ctx.accessor.nodeData i));
  };
  values = ctx: {
    k1v = try (ctx.eval.get "k1" "v");
    sbV = try (ctx.eval.get "s-b" "v");
    hDefs = try (ctx.eval.get "h" "defs");
    allNodeIds = try ctx.eval.allNodeIds;
  };
  # The fields, or the ids within a per-id field, on which two reads differ.
  breaks =
    a: b:
    prelude.concatMap (
      k:
      if builtins.isAttrs b.${k} && k != "trace" then
        map (i: "${k}.${i}") (builtins.filter (i: a.${k}.${i} != b.${k}.${i}) (builtins.attrNames b.${k}))
      else if a.${k} == b.${k} then
        [ ]
      else
        [ k ]
    ) (builtins.attrNames b);
in
{
  flake.tests.warm-sealed-ctx = {
    # ── THE CELL THIS SUITE EXISTS FOR ──
    # The plane accepts the sealed ctx and produces an evaluation from it. Stated separately from
    # the parity claim below because the two fail for different reasons: this one reds when the seal
    # and the plane's read set have drifted apart, which is a shape defect, not a value defect.
    test-the-plane-runs-on-the-sealed-ctx = {
      expr = probe warmed "producer" "p-val";
      expected = 9;
    };

    # Byte-parity (Reps–Teitelbaum–Demers 1983 soundness) through the REAL seal: the warm result
    # equals a cold fold of the same scope with the declaration pre-applied. The other suites make
    # this claim over a hand-built ctx; this is the one that makes it over the assembled one.
    test-sealed-warm-equals-sealed-cold = {
      expr =
        builtins.all (a: probe warmed "consumer" a == probe fresh "consumer" a) [
          "sees"
          "p-val"
        ]
        && probe warmed "producer" "p-val" == probe fresh "producer" "p-val";
      expected = true;
    };

    # THE ARM. `consumer` is not the edited node, so its value moves only if the cone was read
    # correctly off the sealed accessor. Without this the parity cell holds against a plane that
    # recomputed everything AND against one that reused everything, since both sides would agree.
    test-sealed-cone-consumer-is-armed = {
      expr = probe cold "consumer" "sees" != probe fresh "consumer" "sees";
      expected = true;
    };

    # The fold returns a ctx that is still one: the record it hands on carries the edited scope AND
    # the node map in step. A `roots` left at its pre-edit value is a stale map under a live name,
    # and nothing else here would observe it — the plane reads `scope`, so only this cell can.
    test-returned-ctx-keeps-roots-in-step-with-scope = {
      expr = warmed.roots == warmed.scope.nodes && warmed.roots.producer.decls.v == 9;
      expected = true;
    };

    # The seal's own fields survive the fold rather than being dropped by it: the plane returns
    # `ctx // {…}`, so a consumer holding the result still has what the assembler published.
    test-returned-ctx-still-carries-the-seal = {
      expr = builtins.all (f: warmed ? ${f}) [
        "accessor"
        "attributes"
        "declaredDependencies"
        "equations"
        "eval"
        "parseParent"
        "roots"
        "schedule"
        "scope"
        "settings"
        "trace"
      ];
      expected = true;
    };

    # ── THE RETURNED RELATION IS THE WARM EVALUATION'S ──
    # G1. A grown spawn is in the returned node list, which is a fresh fold's.
    test-a-grown-spawn-is-in-the-returned-node-list = {
      expr =
        let
          nodes = (relWarm relCold edits.ES).accessor.nodes;
        in
        {
          inherit nodes;
          grown = builtins.elem "s-b" nodes;
        };
      expected = {
        nodes = (relFold edits.ES).accessor.nodes;
        grown = true;
      };
    };
    # G2. It has its relation: its host.
    test-a-grown-spawn-has-its-relation = {
      expr = try ((relWarm relCold edits.ES).accessor.dependencies "s-b");
      expected = [ "s" ];
    };
    # G3. A child that went leaves the relation: its read refuses, as a fresh fold's does.
    test-a-shrunk-child-leaves-the-relation = {
      expr = try ((relWarm relCold edits.EX).accessor.dependencies (ntaOf "b"));
      expected = "refused";
    };
    # G4. The relation moves with a selection while the node set is held, which a returned node
    # list alone cannot carry.
    test-a-selection-moves-the-relation-with-the-node-set-held = {
      expr = (relWarm relCold edits.EP).accessor.dependencies "p";
      expected = [
        "k1"
        "k2"
      ];
    };
    # G5. The guarded trace lookup is the warm evaluation's.
    test-the-returned-trace-is-the-warm-evaluations = {
      expr = try ((relWarm relCold edits.ES).accessor.trace "s-b");
      expected = {
        deps = [ "s" ];
        hash = null;
      };
    };
    # G6. Three chained edits (growth, growth, shrink), each pass reading the ctx the last one
    # returned, end where a fresh fold of the merged edits does.
    test-three-chained-edits-return-what-a-fresh-fold-returns = {
      expr =
        breaks
          (fingerprint (relChain [
            edits.ES
            edits.EN
            edits.EX
          ]))
          (
            fingerprint (relMerged [
              edits.ES
              edits.EN
              edits.EX
            ])
          );
      expected = [ ];
    };
    # G7. A chain back to the prior keeps its values. Publishing the warm node list against the
    # prior's relation breaks exactly this: the second pass decides over a mismatched pair.
    test-a-chain-back-to-the-prior-keeps-its-values = {
      expr =
        breaks
          (values (relChain [
            edits.ES
            edits.ESback
          ]))
          (
            values (relMerged [
              edits.ES
              edits.ESback
            ])
          );
      expected = [ ];
    };
    # G8. Every derived field of the returned ctx (accessor, trace, roots, the scope's node names,
    # the evaluation's node ids) agrees with a fresh fold: none is carried over from the prior seal.
    test-the-returned-seal-fields-agree-with-a-fresh-fold =
      let
        w = relWarm relCold edits.ES;
        fr = relFold edits.ES;
        wide =
          ctx:
          fingerprint ctx
          // {
            scopeNodes = try (builtins.attrNames ctx.scope.nodes);
            allNodeIds = try ctx.eval.allNodeIds;
          };
      in
      {
        expr = breaks (wide w) (wide fr);
        expected = [ ];
      };
    # G9. An edit nothing reads keeps reuse: the clean `k1` is served from the prior, whose program
    # tags "prior". The returned relation is new; the reused values are not dropped with the old one.
    test-an-unrelated-edit-keeps-reuse = {
      expr = try (
        (relWarm (relCold // { inherit (relFoldWith "prior" { }) eval; }) edits.EZ).eval.get "k1" "tag"
      );
      expected = "prior";
    };
    # The memo ctx the fold returns beside the seal traces the same relation: its trace is built over
    # the returned accessor, so the grown spawn and the moved selection are in it.
    test-the-returned-memo-ctx-traces-the-warm-relation = {
      expr =
        let
          grown = (relWarm relCold edits.ES).builtCtx.trace;
          selected = (relWarm relCold edits.EP).builtCtx.trace;
        in
        {
          grown = try (if grown ? "s-b" then grown."s-b".deps else "absent");
          selected = try selected.p.deps;
        };
      expected = {
        grown = [ "s" ];
        selected = [
          "k1"
          "k2"
        ];
      };
    };

    # ── THE ENGINE RECORD ──
    # An engine carrying only `evalWarm`, the record this fold took before it was sealed through
    # `foldEquations`, is refused catchably (the message is pinned in `ci/tests-error.nix`).
    test-an-evalWarm-only-engine-is-refused-catchably = {
      expr =
        (builtins.tryEval (warmOverride { inherit (genScope) evalWarm; } relCold "k2" { v = 9; })).success;
      expected = false;
    };
    # Control: the record a caller now hands, `foldEquations` alone, runs the warm pass.
    test-control-a-foldEquations-engine-runs-the-warm-pass = {
      expr = try (
        (warmOverride { inherit (genScope) foldEquations; } relCold "s" edits.ES.s).accessor.dependencies
          "s-b"
      );
      expected = [ "s" ];
    };
  };
}
