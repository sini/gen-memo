# THE UNION RELATION, AT THE PLANE THAT CONSUMES IT.
#
# `accessor.dependencies` is the NORMALIZED UNION of two relations — the structural one a substrate
# projects from its child-bearing and reference-bearing attributes, and the declared one a node's
# equations name. gen-scope constructs that union at one site
# (`lib/fold-equations.nix:99` — `dependencies = id: prelude.unique (ev.structuralEdges id ++
# declaredDependencies id)`) and the seal's `trace.deps` derives from the same expression. This
# suite is the CONSUMER's half: it drives the plane's real reuse predicate over a union-shaped
# relation and pins the two behaviours that the union exists to produce.
#
# ★★★ WHY A UNION AT ALL — THE DEFECT IT FIXES, KEPT AS A CELL RATHER THAN AS HISTORY. The plane
# once read the DECLARED relation alone. A parent reaches its children's declarations through a
# self-read that crosses neither guarded seam, so a parent's value is a function of a child it
# never declared: change the child, and the declared-only cone does not contain the parent, and the
# parent is SERVED STALE. That is a parity failure by ADR-0008 item 2's own definition. The seeded
# declared-only arm below is that defect, reproduced end to end — it is the cell that would have
# caught it, and it is written so a future editor who narrows the relation back reds it.
#
# ★★★ THE IDENTITY THE PREDICATE RESTS ON, AND WHY NORMALIZATION IS PART OF IT.
# `strategies.verify` compares with Nix LIST equality —
# `lib/strategies.nix:17`: `depsMatch = ctx.trace.${id}.deps == accessor'.dependencies id` — so the
# seal's relation and the accessor's must agree as lists: same members, same multiplicity, same
# order. The declared relation carries no duplicates, so this asymmetry was invisible until the
# union existed; the union is what first makes a node appear TWICE, once from each half. A raw
# union in the trace against a deduplicated accessor makes `depsMatch` false for exactly the
# overlapping nodes, and `verify` then returns `reuse = false` for them PERMANENTLY and SILENTLY —
# a reuse loss, never a wrong value, which is why no value-comparing cell can see it and why the
# cells here assert on the reuse decision itself.
#
# ★★ WHAT THIS SUITE DOES NOT COVER, stated so its green is not read as wider than it is. It drives
# CONSTRUCTED accessor records; it never observes a producer. That all producers of this relation
# bind through the `.dependencies` field was established by READING at pinned revisions, and
# nothing here arms it: a new producer that wrote the trace from some other relation would redden
# no cell in this file. The identity's instrument coverage ends at the constructed-record boundary,
# and a future author adding a producer owes that read again. This limit is stated by design and is
# deliberately NOT armed — arming it needs an oracle over producers, which is a different subject.
{
  lib,
  genMemo,
  prelude,
  engine,
  ...
}:
let
  build = genMemo.build engine;
  override = genMemo.override engine;
  inherit (genMemo) verify;

  # ---- THE FIXTURE ----------------------------------------------------------------------------
  #
  #   top ──declared──▶ p
  #   p ──structural──▶ c , e
  #   p ──declared────▶ d , c
  #
  # ★★★ `c` IS IN BOTH HALVES AND `e` IS IN THE STRUCTURAL HALF ONLY. Both members are required and
  # neither substitutes for the other:
  #
  #   · `c` is what makes the raw union CARRY A DUPLICATE (`["c" "e" "d" "c"]`), so it is the only
  #     node that can detect an un-normalized union. A fixture whose nodes appear in one relation
  #     each produces a raw union already equal to its normalization, and goes GREEN on the broken
  #     code — that is the blind fixture, reproduced as a control below rather than described.
  #   · `e` is what makes the declared-only relation UNSOUND, so it is the only node that can
  #     detect the stale serve. A fixture whose structural edges are all also declared cannot
  #     distinguish the union from the declared relation at all.
  weights = {
    top = 1;
    p = 2;
    d = 10;
    c = 100;
    e = 1000;
  };
  allNodes = [
    "top"
    "p"
    "d"
    "c"
    "e"
  ];

  structuralOf =
    id:
    if id == "p" then
      [
        "c"
        "e"
      ]
    else
      [ ];
  declaredOf =
    id:
    if id == "top" then
      [ "p" ]
    else if id == "p" then
      [
        "d"
        "c"
      ]
    else
      [ ];

  mkAcc = deps: {
    nodes = allNodes;
    dependencies = deps;
    nodeData = id: { weight = weights.${id}; };
    parent = _id: null;
  };

  # THE UNION, written verbatim in gen-scope's shape rather than paraphrased: one `prelude.unique`
  # over the concatenation, at ONE site. The single construction site is what makes the ORDER half
  # of the identity free — the trace derives from this same expression, so the two sides are the
  # same list because they are the same expression, not because both ends sort.
  unionAcc = mkAcc (id: prelude.unique (structuralOf id ++ declaredOf id));
  # The pre-union relation, kept as a SUBJECT so the defect it caused can be measured, not recalled.
  declaredOnlyAcc = mkAcc declaredOf;
  # The un-normalized union — the seed for the identity cells. NOT a shipped shape.
  rawUnionOf = id: structuralOf id ++ declaredOf id;

  recompute =
    a: s: id:
    (a.nodeData id).weight + lib.foldl' (sum: dep: sum + s.${dep}) 0 (a.dependencies id);
  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  uCtx = build {
    accessor = unionAcc;
    inherit recompute hashOf;
  };
  dCtx = build {
    accessor = declaredOnlyAcc;
    inherit recompute hashOf;
  };

  # ---- DRIVING THE REAL PREDICATE -------------------------------------------------------------
  #
  # `verify ctx { accessor', spliced } id`. The topology never moves in these cells (`accessor'` is
  # the ctx's own accessor), so the only thing that varies is the candidate store — which is what
  # makes every `reuse = false` below the deps predicate or the hash gate talking, and nothing else.
  reuseOf =
    ctx: spliced: id:
    (verify ctx {
      accessor' = ctx.accessor;
      inherit spliced;
    } id).reuse;

  # A ctx whose trace carries the RAW union for one node, the accessor still deduplicating.
  seedRawTrace =
    ctx: id:
    ctx
    // {
      trace = ctx.trace // {
        ${id} = ctx.trace.${id} // {
          deps = rawUnionOf id;
        };
      };
    };
in
{
  flake.tests."union-relation" = {
    # ===== THE FIXTURE, PINNED ================================================================
    #
    # Asserted before anything is concluded from it: every cell below reads one of these two
    # relations, and a fixture that had quietly stopped carrying the overlap or the structural-only
    # edge would make the arms pass for reasons unrelated to what they claim.

    # ★ THE DUPLICATE IS REAL. This is the premise O4 names as mandatory — the raw union of a node
    # in BOTH relations carries `c` twice — and it is asserted rather than assumed.
    test-control-raw-union-carries-the-duplicate = {
      expr = rawUnionOf "p";
      expected = [
        "c"
        "e"
        "d"
        "c"
      ];
    };

    # And the normalization removes it, leaving first-occurrence order.
    test-union-is-normalized = {
      expr = unionAcc.dependencies "p";
      expected = [
        "c"
        "e"
        "d"
      ];
    };

    # The declared-only relation does NOT contain the structural-only child. This is the whole of
    # the stale-serve mechanism, stated as data.
    test-control-declared-only-omits-the-structural-child = {
      expr = declaredOnlyAcc.dependencies "p";
      expected = [
        "d"
        "c"
      ];
    };

    test-control-union-store-baseline = {
      expr = uCtx.store;
      expected = {
        c = 100;
        d = 10;
        e = 1000;
        p = 1112;
        top = 1113;
      };
    };

    # ===== O4 · THE IDENTITY, AND THE REAL-VERIFY CONTROL PAIR =================================

    # `trace.<id>.deps` and `accessor'.dependencies id` are the SAME LIST for the node that sits in
    # both relations. This is the identity `depsMatch` rests on, asserted at the node where it can
    # actually fail.
    test-o4-identity-holds-for-the-node-in-both-relations = {
      expr = uCtx.trace."p".deps == unionAcc.dependencies "p";
      expected = true;
    };

    # ★ THE CONTROL PAIR, BOTH HALVES IN THE SAME RUN. A clean node reuses …
    test-o4-clean-node-reuses = {
      expr = reuseOf uCtx uCtx.store "p";
      expected = true;
    };

    # … and a genuinely dirty node refuses. Without this half the cell above passes a `verify` that
    # returns `true` unconditionally; without the half above, one that returns `false`.
    test-o4-dirty-node-refuses = {
      expr = reuseOf uCtx (uCtx.store // { c = 999; }) "p";
      expected = false;
    };

    # ★★★ THE SEEDED DEFECT: the raw union in the trace against the deduplicated accessor. Nothing
    # has changed between the two sides — the store is the clean one — so this `false` is the
    # multiplicity divergence and nothing else. This is the reuse loss the normalization prevents,
    # and it is measured rather than argued.
    test-o4-seeded-raw-trace-loses-reuse = {
      expr = reuseOf (seedRawTrace uCtx "p") uCtx.store "p";
      expected = false;
    };

    # ★★★ THE BLIND FIXTURE, REPRODUCED. `top` is in the declared relation only, so its raw union
    # and its normalization are the same list — the seed above is a NO-OP on it and reuse survives.
    # A suite whose fixture placed every node in one relation would therefore report the broken
    # code CLEAN. This cell is why the overlap at `p` is a requirement of the fixture and not a
    # detail of it.
    test-control-blind-fixture-goes-green-on-the-same-seed = {
      expr = reuseOf (seedRawTrace uCtx "top") uCtx.store "top";
      expected = true;
    };

    # ===== THE PLANE-SIDE UNION SEMANTICS, END TO END =========================================
    #
    # The cells above drive `verify` directly. These drive the plane's real driver — `override`,
    # which is `propagate ∘ applyDelta` — so what they measure is the SERVED VALUE, not a predicate
    # about it. The stale serve is a wrong value reaching a caller; it deserves a cell that reads
    # one.

    # ★★★ THE FIXED BEHAVIOUR. `e` is a structural-only child of `p`. Changing it moves `p`, because
    # the union puts `e` in `p`'s dependency relation: p = 2 + c(100) + e(9999) + d(10).
    test-union-propagates-a-structural-only-child-change = {
      expr = (override uCtx "e" { weight = 9999; }).store."p";
      expected = 10111;
    };

    # ★★★ THE SEEDED DEFECT, END TO END — the declared-only relation SERVES STALE. `p`'s value is
    # a function of `e`, `e` moved, and `p` comes back at its old value because the declared-only
    # cone never contained it. The expectation is the STALE number on purpose: this cell asserts
    # the defect exists in the relation it names, so that a change restoring that relation is
    # caught by the pair of cells rather than by neither.
    test-seed-declared-only-serves-a-stale-parent = {
      expr = (override dCtx "e" { weight = 9999; }).store."p";
      expected = 112;
    };

    # ★ THE DISCRIMINATOR. The same declared-only relation DOES propagate a change to a DECLARED
    # child. Without this, the stale serve above is indistinguishable from a fixture in which
    # nothing propagates at all — the cell would pass a totally inert plane.
    test-control-declared-only-propagates-a-declared-child-change = {
      expr = (override dCtx "c" { weight = 999; }).store."p";
      expected = 1011;
    };

    # ★ THE ⊤ CONTROL. The union does not refuse everything: a change to an UNRELATED node leaves
    # `p` reusing. Without it, `test-union-propagates-a-structural-only-child-change` passes a
    # relation that dirties the whole graph on any edit.
    test-control-union-leaves-an-unrelated-node-clean = {
      expr = reuseOf uCtx (uCtx.store // { top = 424242; }) "p";
      expected = true;
    };

    # ★ AND THE OVERLAP MEMBER, END TO END. `c` is declared AND a structural child; it must
    # propagate exactly once — p = 2 + c(999) + e(1000) + d(10). A union that failed to deduplicate
    # would double-count `c` here and yield 3010, which is the arithmetic form of the same defect
    # `test-o4-seeded-raw-trace-loses-reuse` catches as a reuse loss.
    test-union-counts-the-overlapping-child-once = {
      expr = (override uCtx "c" { weight = 999; }).store."p";
      expected = 2011;
    };
  };
}
