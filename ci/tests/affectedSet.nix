# Direct tests for affectedSet — exact AFFECTED via hash post-filter over the cone
# (RTD 1983 §4.3). affectedSet ctx { accessor'; changedIds } -> { affected; hashes;
# reused }: `affected` = cone nodes whose hash moved, `reused` = the rest, `hashes` =
# per-cone-node new hash. The over-approx cone (dirtySet) stays the recompute domain.
{
  lib,
  genMemo,
  graph,
  engine,
  fx,
  ...
}:
let
  build = genMemo.build engine;
  affectedSet = genMemo.affectedSet engine;
  inherit (genMemo) dirtySet;

  recompute =
    a: s: id:
    (a.nodeData id).weight + lib.foldl' (sum: dep: sum + s.${dep}) 0 (a.dependencies id);
  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  # chain a -> b -> c (a deps b, b deps c). ctx.store: c=100, b=110, a=111.
  acc = fx.mkPlaneAccessor {
    edges = [
      {
        from = "a";
        to = "b";
      }
      {
        from = "b";
        to = "c";
      }
    ];
    nodeData = {
      a = {
        weight = 1;
      };
      b = {
        weight = 10;
      };
      c = {
        weight = 100;
      };
    };
  };
  ctx = build {
    accessor = acc;
    inherit recompute hashOf;
  };

  # Override leaf c := 200. cone = {a,b,c}; ALL three values move (c=200,b=210,a=211).
  accC = acc // {
    nodeData = id: if id == "c" then { weight = 200; } else acc.nodeData id;
  };
  affC = affectedSet ctx {
    accessor' = accC;
    changedIds = [ "c" ];
  };

  # Override root a := 5. cone = {a} (nothing depends on a). Only a moves (115).
  accA = acc // {
    nodeData = id: if id == "a" then { weight = 5; } else acc.nodeData id;
  };
  affA = affectedSet ctx {
    accessor' = accA;
    changedIds = [ "a" ];
  };

  # --- value-collision: abs(weight - 50) so a changed-weight can keep its value ---
  absRecompute =
    a: _s: id:
    let
      x = (a.nodeData id).weight - 50;
    in
    if x < 0 then -x else x;
  collAcc = fx.mkPlaneAccessor {
    nodeData = {
      l = {
        weight = 30;
      };
    };
  };
  collCtx = build {
    accessor = collAcc;
    recompute = absRecompute;
    hashOf = hashOf;
  };
  # |30-50| = 20; override to weight 70 ⇒ |70-50| = 20 (collision). Nothing affected.
  collAcc' = collAcc // {
    nodeData = id: if id == "l" then { weight = 70; } else collAcc.nodeData id;
  };
  affColl = affectedSet collCtx {
    accessor' = collAcc';
    changedIds = [ "l" ];
  };

  # --- function-bearing node (hash = null) is always affected when in the cone ---
  lambdaAcc = fx.mkPlaneAccessor {
    nodeData = {
      f = { };
    };
  };
  lambdaCtx = build {
    accessor = lambdaAcc;
    recompute = _acc: _s: _id: { fn = x: x + 1; };
    inherit hashOf;
  };
  affLambda = affectedSet lambdaCtx {
    accessor' = lambdaAcc;
    changedIds = [ "f" ];
  };

  # ===== cyclic-cone guard (den-hoag-xyme) =====
  # Same 2-SCC {x,y}/producer p/consumer c shape as drivers.nix's/eager.nix's
  # cyclic-cone fixtures, reconstructed locally per this file's own convention.
  # Built via `fixpoint` (build's STRATIFIED arm) — a bare `build` without one
  # throws unconditionally on ANY cyclic accessor regardless of the edit that
  # follows, which would test nothing about affectedSet's own guard.
  cyclicAcc = fx.mkPlaneAccessor {
    edges = [
      {
        from = "x";
        to = "y";
      }
      {
        from = "y";
        to = "x";
      }
      {
        from = "x";
        to = "p";
      }
      {
        from = "c";
        to = "y";
      }
    ];
    nodeData = {
      p = {
        weight = 5;
      };
      x = {
        weight = 1;
      };
      y = {
        weight = 1;
      };
      c = {
        weight = 0;
      };
    };
  };
  cyclicIds = [
    "p"
    "x"
    "y"
    "c"
  ];
  # max-over-deps: idempotent, actually converges on the {x,y} SCC (an additive
  # recompute would climb without bound and never reach a fixpoint at all).
  cyclicRecompute =
    a: s: id:
    lib.foldl' lib.max (a.nodeData id).weight (map (d: s.${d}) (a.dependencies id));
  cyclicCtx = build {
    accessor = cyclicAcc;
    recompute = cyclicRecompute;
    inherit hashOf;
    fixpoint = {
      lattices = lib.genAttrs cyclicIds (_: {
        bottom = 0;
        join = _: v: v;
        eq = (a: b: a == b);
        maxIter = 100;
      });
    };
  };
  cyclicAccReaches = cyclicAcc // {
    nodeData = id: if id == "p" then { weight = 50; } else cyclicAcc.nodeData id;
  };
  cyclicAccMisses = cyclicAcc // {
    nodeData = id: if id == "c" then { weight = 999; } else cyclicAcc.nodeData id;
  };
  # Unlike eager.nix's `propagateEager` (an unconditional attrset literal —
  # forcing a field is required to reach the hazard), `affectedSet`'s guard IS
  # the function's own outermost expression (`if cyclicInCone != [] then throw
  # else {...}`), so a bare `tryEval` on the call already forces the branch.
  affectedReachesCycle = builtins.tryEval (
    affectedSet cyclicCtx {
      accessor' = cyclicAccReaches;
      changedIds = [ "p" ];
    }
  );
  affectedMissesCycle = builtins.tryEval (
    affectedSet cyclicCtx {
      accessor' = cyclicAccMisses;
      changedIds = [ "c" ];
    }
  );
in
{
  flake.tests."affectedSet" = {
    # ===== full move: leaf change moves the whole chain =====
    test-affected-c-all = {
      expr = builtins.sort builtins.lessThan affC.affected;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-reused-c-empty = {
      expr = affC.reused;
      expected = [ ];
    };
    test-hashes-c-leaf = {
      expr = affC.hashes.c;
      expected = hashOf 200;
    };
    test-hashes-c-root = {
      expr = affC.hashes.a;
      expected = hashOf 211;
    };

    # ===== root change: cone is just {a}; only a is affected =====
    test-affected-a-only = {
      expr = affA.affected;
      expected = [ "a" ];
    };
    test-hashes-a = {
      expr = affA.hashes.a;
      expected = hashOf 115;
    };

    # ===== affected ⊆ cone (subset of the over-approx reachable set) =====
    test-affected-subset-cone-c = {
      expr = builtins.all (id: builtins.elem id (dirtySet ctx [ "c" ])) affC.affected;
      expected = true;
    };

    # ===== value collision ⇒ AFFECTED is empty (RTD: value unchanged ⇒ not affected) =====
    test-affected-empty-on-collision = {
      expr = affColl.affected;
      expected = [ ];
    };
    test-reused-on-collision = {
      expr = affColl.reused;
      expected = [ "l" ];
    };

    # ===== function-bearing (hash = null) node is always affected (always-dirty) =====
    test-affected-null-hash = {
      expr = affLambda.affected;
      expected = [ "f" ];
    };
    test-hashes-null-hash = {
      expr = affLambda.hashes.f;
      expected = null;
    };

    # ===== cyclic-cone guard (den-hoag-xyme) =====
    test-control-cyclic-fixture-is-a-genuine-scc = {
      expr = builtins.sort builtins.lessThan (graph.cycles (fx.graphOf cyclicAcc));
      expected = [
        "x"
        "y"
      ];
    };
    test-affectedSet-refuses-cyclic-cone = {
      expr = affectedReachesCycle.success;
      expected = false;
    };
    test-control-affectedSet-cyclic-ctx-safe-edit-still-works = {
      expr = affectedMissesCycle.success;
      expected = true;
    };
    test-control-affectedSet-cyclic-ctx-safe-edit-value = {
      expr = affectedMissesCycle.value.hashes.c;
      expected = hashOf 999;
    };
  };
}
