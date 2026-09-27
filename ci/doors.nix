# THE CLOSED-DOOR TABLE (den-hoag-7gp66 P1) — one row per closed record gen-memo publishes, read by
# `ci/tests/door-checks.nix` (catchability) and `ci/tests-error.nix` (the refusal bytes). It lives
# outside ./tests so the harness does not collect it as a test module.
#
# A row is the door's name as its refusal spells it, its required fields, its options (`[ ]` for a
# RECORD door, R5: open, an extra field admitted; non-empty for a MIXED door, closed over the whole
# set until P2), a VALID record, and `call`, which applies the door to a record as far as the door's
# own check runs. `call valid` must answer: that is each row's live control, so a refusal below is
# the check firing and not a broken fixture.
#
# FOURTEEN DOORS, FIFTEEN RECORDS. `earlyCutoff` takes two closed records, one per curry position.
# `identitiesHeld` is a door although no top-level export names it: `warmDecision` returns it in its
# public decision record, and a caller applies it to identity maps of its own.
{
  lib,
  genMemo,
  genScope,
  engine,
  fx,
}:
let
  recompute =
    a: s: id:
    (a.nodeData id).weight + lib.foldl' (sum: dep: sum + s.${dep}) 0 (a.dependencies id);
  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  # chain a -> b -> c.
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
      a.weight = 1;
      b.weight = 10;
      c.weight = 100;
    };
  };
  ctx = genMemo.build engine {
    accessor = acc;
    inherit recompute hashOf;
  };

  decision = genMemo.warmDecision {
    accessor = {
      nodes = [ ];
      dependencies = _: [ ];
    };
    prior.resolutional = _: [ ];
  } [ ];

  # A warm-capable ctx, as `ci/tests/warm-resolve.nix` builds one.
  warmCtx =
    let
      scope = genScope.buildRoots {
        kinds = genScope.mkKinds [ (genScope.mkKind { name = "host"; }) ];
        decls.a.v = 1;
        types.a = "host";
      };
      attributes = {
        children = _self: _id: { };
        self-v = self: id: (self.node id).decls.v;
        imports = _self: _id: [ ];
      };
      parseParent = _: null;
      eval = genScope.eval { inherit scope attributes parseParent; };
    in
    {
      inherit
        scope
        attributes
        parseParent
        eval
        ;
      roots = scope.nodes;
      declaredDependencies = _: [ ];
      accessor = {
        nodes = builtins.attrNames eval.allNodes;
        dependencies = _: [ ];
        parent = parseParent;
        nodeData = id: (eval.node id).decls or { };
      };
    };

  setLattice = {
    bottom = [ ];
    join = x: y: lib.sort builtins.lessThan (lib.unique (x ++ y));
    maxIter = 100;
  };
in
{
  mkAccessor = {
    required = [
      "dependencies"
      "nodes"
      "nodeData"
      "parent"
    ];
    options = [ ];
    valid = {
      dependencies = _: [ ];
      nodes = [ ];
      nodeData = _: { };
      parent = _: null;
    };
    call = genMemo.mkAccessor;
  };

  verify = {
    required = [
      "accessor'"
      "spliced"
    ];
    options = [ ];
    valid = {
      "accessor'" = acc;
      spliced = ctx.store;
    };
    call = args: genMemo.verify ctx args;
  };

  # The first record: `{ hashOf }`.
  earlyCutoff-hashOf = {
    door = "earlyCutoff";
    required = [ "hashOf" ];
    options = [ ];
    valid = { inherit hashOf; };
    call = genMemo.earlyCutoff;
  };

  # The second record: `{ oldHash, newValue }`.
  earlyCutoff-value = {
    door = "earlyCutoff";
    required = [
      "oldHash"
      "newValue"
    ];
    options = [ ];
    valid = {
      oldHash = null;
      newValue = 1;
    };
    call = genMemo.earlyCutoff { inherit hashOf; };
  };

  needsEval = {
    required = [
      "trace"
      "coneSet"
      "newHashOf"
      "accessor'"
    ];
    options = [ ];
    valid = {
      inherit (ctx) trace;
      coneSet = { };
      newHashOf = _: null;
      "accessor'" = acc;
    };
    call = genMemo.needsEval;
  };

  affectedSet = {
    required = [
      "accessor'"
      "changedIds"
    ];
    options = [ ];
    valid = {
      "accessor'" = acc;
      changedIds = [ "c" ];
    };
    call = genMemo.affectedSet engine ctx;
  };

  build = {
    required = [
      "accessor"
      "recompute"
      "hashOf"
    ];
    options = [ "fixpoint" ];
    valid = {
      accessor = acc;
      inherit recompute hashOf;
    };
    call = genMemo.build engine;
  };

  why = {
    required = [
      "id"
      "changedId"
    ];
    options = [ "cutoffs" ];
    valid = {
      id = "a";
      changedId = "c";
    };
    call = genMemo.why ctx;
  };

  whyFor = {
    required = [ "changedId" ];
    options = [ "cutoffs" ];
    valid.changedId = "c";
    call = genMemo.whyFor ctx;
  };

  warmDecision = {
    required = [
      "accessor"
      "prior"
    ];
    options = [ ];
    valid = {
      accessor = {
        nodes = [ ];
        dependencies = _: [ ];
      };
      prior.resolutional = _: [ ];
    };
    call = genMemo.warmDecision;
  };

  identitiesHeld = {
    required = [
      "priorIdentities"
      "nextIdentities"
    ];
    options = [ "remerged" ];
    valid = {
      priorIdentities = { };
      nextIdentities = { };
    };
    call = decision.identitiesHeld;
  };

  warmTrace = {
    required = [
      "edited"
      "decision"
    ];
    options = [ ];
    valid = {
      edited = false;
      decision = { };
    };
    call = genMemo.warmTrace;
  };

  warmOverride = {
    required = [
      "id"
      "newDecls"
    ];
    options = [ ];
    valid = {
      id = "a";
      newDecls.v = 5;
    };
    call = genMemo.warmOverride engine warmCtx;
  };

  warmResolve = {
    required = [ "edits" ];
    options = [ ];
    valid.edits.a.v = 5;
    call = genMemo.warmResolve engine warmCtx;
  };

  runScc = {
    required = [
      "accessor"
      "store"
      "recompute"
      "scc"
      "higherStrata"
      "lattices"
    ];
    options = [ ];
    valid = {
      accessor = fx.mkPlaneAccessor {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "a";
          }
        ];
        nodeData = {
          a = { };
          b = { };
        };
      };
      store = { };
      higherStrata = { };
      recompute =
        a: s: m:
        lib.sort builtins.lessThan (lib.unique ([ m ] ++ s.${builtins.head (a.dependencies m)}));
      scc = [
        "a"
        "b"
      ];
      lattices = {
        a = setLattice;
        b = setLattice;
      };
    };
    call = genMemo.runScc engine.ascend;
  };
}
