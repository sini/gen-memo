# THE DOOR TABLE (den-hoag-7gp66 P1, then P2 — `prelude.door`) — every published step of gen-memo
# that takes a RECORD, read by `ci/tests/door-checks.nix` (catchability, contracts, the guard) and
# `ci/tests-error.nix` (the refusal bytes). It lives outside ./tests so the harness does not collect
# it as a test module.
#
# After P2 a door is one of two steps (R7). An OPTIONS step is a closed set, first in the call: a
# row is the door and its `optional` names. A RECORD step is an open data record (R5): a row is the
# step as applied (every earlier operand already supplied), its `required` fields, a `good` record,
# the field `drop` removes for the missing-field cell, and — for a record behind an options step —
# `guardedBy`, the options row whose names the record refuses (`optionsStep`, G10). `step good` must
# answer: that is each row's live control, so a refusal below is the check firing and not a broken
# fixture.
#
# The positional doors (`verify`, `earlyCutoff`, `affectedSet`, `warmDecision`, `warmOverride`,
# `warmResolve`, `warmTrace`) carry no row: their arity is structural and they have no field check.
# `identitiesHeld` is a door although no top-level export names it: `warmDecision` returns it in its
# public decision record, and a caller applies it to identity maps of its own.
{
  lib,
  genMemo,
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
  ctx = genMemo.build { } engine {
    accessor = acc;
    inherit recompute hashOf;
  };

  decision = genMemo.warmDecision {
    nodes = [ ];
    dependencies = _: [ ];
  } { resolutional = _: [ ]; } [ ];

  setLattice = {
    bottom = [ ];
    join = x: y: lib.sort builtins.lessThan (lib.unique (x ++ y));
    maxIter = 100;
  };
in
{
  inherit ctx acc;

  options = {
    build = {
      door = genMemo.build;
      optional = [ "fixpoint" ];
    };
    why = {
      door = genMemo.why;
      optional = [ "cutoffs" ];
    };
    whyFor = {
      door = genMemo.whyFor;
      optional = [ "cutoffs" ];
    };
    whyNot = {
      door = genMemo.whyNot;
      optional = [ "cutoffs" ];
    };
    whyNotFor = {
      door = genMemo.whyNotFor;
      optional = [ "cutoffs" ];
    };
    identitiesHeld = {
      door = decision.identitiesHeld;
      optional = [ "remerged" ];
    };
  };

  # The options doors whose next step is not a record: the provenance queries take the ctx and
  # positional ids after their options.
  notChained = [
    "why"
    "whyFor"
    "whyNot"
    "whyNotFor"
  ];

  records = {
    build = {
      step = genMemo.build { } engine;
      required = [
        "accessor"
        "recompute"
        "hashOf"
      ];
      good = {
        accessor = acc;
        inherit recompute hashOf;
      };
      drop = "hashOf";
      guardedBy = "build";
    };

    identitiesHeld = {
      step = decision.identitiesHeld { };
      required = [
        "priorIdentities"
        "nextIdentities"
      ];
      good = {
        priorIdentities = { };
        nextIdentities = { };
      };
      drop = "nextIdentities";
      guardedBy = "identitiesHeld";
    };

    mkAccessor = {
      step = genMemo.mkAccessor;
      required = [
        "dependencies"
        "nodes"
        "nodeData"
        "parent"
      ];
      good = {
        dependencies = _: [ ];
        nodes = [ ];
        nodeData = _: { };
        parent = _: null;
      };
      drop = "parent";
    };

    needsEval = {
      step = genMemo.needsEval;
      required = [
        "trace"
        "coneSet"
        "newHashOf"
        "accessor'"
      ];
      good = {
        inherit (ctx) trace;
        coneSet = { };
        newHashOf = _: null;
        "accessor'" = acc;
      };
      drop = "accessor'";
    };

    runScc = {
      step = genMemo.runScc engine.ascend;
      required = [
        "accessor"
        "store"
        "recompute"
        "scc"
        "higherStrata"
        "lattices"
      ];
      good = {
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
      drop = "lattices";
    };
  };
}
