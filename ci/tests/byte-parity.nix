# BYTE-PARITY AGAINST COLD EVALUATION — the plane's definition, armed as an instrument.
#
# A plane output is byte-identical to a cold evaluation of the same input. This is a DEFINITION
# rather than a test target: a plane that is fast and not byte-parity is not a faster plane, it is
# a wrong one, and it follows that the plane has no semantics of its own — anything it can express
# that a cold evaluation cannot is a defect.
#
# THE INSTRUMENT, exactly: the same input evaluated twice, once with the decision forced to
# NOTHING IS CLEAN, compared on `drvPath` where the output is a derivation and on the value
# otherwise. Forcing the decision to nothing-is-clean is what `build` over the changed accessor
# already is — it consults no prior and recomputes every node — so the cold arm is the decision
# REMOVED rather than a second implementation of it.
#
# WHAT THIS INSTRUMENT PRESUMES RATHER THAN ESTABLISHES: a matching prior. "The same input
# evaluated twice" fixes the PROGRAM across the two runs; it does not check that the warm arm's
# prior came from that program. Here nothing else is possible — the prior is the same evaluation's
# own `build` result, so the presumption holds BY CONSTRUCTION and not by this instrument. Were a
# prior ever to arrive as an input, this instrument would still not see a mismatched one, and a
# prior-provenance instrument would be owed before that step could be taken.
#
# ★★ WHICH HALF OF THE COMPARATOR IS ARMED WHERE, because the two are not armed the same way and
# reading them as one would claim coverage this file has not got.
#
#   THE VALUE BRANCH is armed END-TO-END, through the plane: four decision paths, each compared
#   against a cold build of the same edited input.
#
#   THE DERIVATION BRANCH is armed AT THE COMPARATOR, not through the plane, and the reason is a
#   MEASURED DEFECT in the content this library received. `hash.nix`'s `containsFunction` walks a
#   value structurally with no cycle guard, and a Nix derivation IS self-referential — `drv.all`'s
#   first element is the derivation itself (measured: `(builtins.elemAt drv.all 0) == drv` is
#   true). So a raw derivation handed to the hash guard descends forever and aborts with a stack
#   overflow that `builtins.tryEval` DOES NOT CONTAIN (measured; live controls in the same run:
#   the same predicate answers `true` on `{ a = x: x; }` and `false` on `{ a = 1; b = [ 2 3 ]; }`).
#   No cell can pin an uncatchable abort — it takes the whole evaluation with it — so the defect is
#   recorded here rather than asserted, and the plane arm below carries each node's drvPath, which
#   is the derivation's evaluation identity and exactly what the comparator reads anyway.
#
#   ⇒ The consequence, stated plainly rather than left to be inferred: the store's admissible
#   values today are function-free AND acyclic, and a derivation is neither. The null-hash rule
#   records the first partiality of Nix hashing; this is a second one, and it is not conservative
#   the way the first is — it does not fall back to always-dirty, it aborts.
{
  genMemo,
  graph,
  lib,
  ...
}:
let
  inherit (genMemo)
    build
    override
    propagate
    propagateEager
    batch
    restabilize
    ;

  # THE COMPARATOR. A derivation is compared on `drvPath` — its identity as a build — and anything
  # else on the value itself. `drvPath` and not `outPath`: a derivation's identity is fixed at
  # evaluation while its output is fixed by running it, and this is a claim about evaluation.
  observe = v: if builtins.isAttrs v && v ? drvPath then v.drvPath else v;
  observeStore = store: lib.mapAttrs (_: observe) store;

  hashOf = v: builtins.hashString "sha256" (builtins.toJSON (observe v));

  mkDrv =
    name: inputs: w:
    derivation {
      inherit name;
      # A literal system, never `builtins.currentSystem`: this suite compares drvPaths and never
      # builds anything, and `currentSystem` is absent under the pure evaluation the runner uses.
      system = "x86_64-linux";
      builder = "/bin/sh";
      args = [
        "-c"
        "true"
      ];
      inherit inputs;
      w = builtins.toString w;
    };

  # ── Fleet shape: a shared producer and three consumers. ──
  fleetAcc = graph.mkGraph {
    edges = [
      {
        from = "h1";
        to = "shared";
      }
      {
        from = "h2";
        to = "shared";
      }
      {
        from = "h3";
        to = "shared";
      }
    ];
    nodeData = {
      shared = {
        w = 10;
      };
      h1 = {
        w = 1;
      };
      h2 = {
        w = 2;
      };
      h3 = {
        w = 3;
      };
    };
  };

  valueRecompute =
    acc: s: id:
    (acc.nodeData id).w + builtins.foldl' (sum: d: sum + s.${d}) 0 (acc.edges id);

  # The derivation arm's node value is the drvPath — see the header. The dependency edge is real:
  # a node's derivation takes its producers' drvPaths as inputs, so a producer whose identity
  # moved moves every consumer's identity with it.
  drvPathRecompute =
    acc: s: id:
    (mkDrv "gen-memo-parity-${id}" (map (d: s.${d}) (acc.edges id)) (acc.nodeData id).w).drvPath;

  changedAccessor =
    accessor: changedId: newDecls:
    accessor
    // {
      nodeData = id: if id == changedId then newDecls else accessor.nodeData id;
    };

  # THE INSTRUMENT. `warmOf` names which plane operation is under test, so each arm below is the
  # same comparison over a different decision path rather than four hand-written comparisons.
  parity =
    {
      accessor,
      recompute,
      changedId,
      newDecls,
      warmOf,
    }:
    let
      ctx = build { inherit accessor recompute hashOf; };
      cold = build {
        accessor = changedAccessor accessor changedId newDecls;
        inherit recompute hashOf;
      };
    in
    {
      warm = observeStore (warmOf ctx).store;
      cold = observeStore cold.store;
    };

  parityHolds =
    args:
    let
      p = parity args;
    in
    p.warm == p.cold;

  editArgs = recompute: warmOf: {
    accessor = fleetAcc;
    changedId = "shared";
    newDecls = {
      w = 100;
    };
    inherit recompute warmOf;
  };
  valueArgs = editArgs valueRecompute;
  drvArgs = editArgs drvPathRecompute;

  # ── The cyclic arm: its cold side is a STRATIFIED build, so it is spelled out rather than
  # routed through `parity`. ──
  cyclicAcc = graph.mkGraph {
    edges = [
      {
        from = "p";
        to = "q";
      }
      {
        from = "q";
        to = "p";
      }
      {
        from = "r";
        to = "p";
      }
    ];
    nodeData = {
      p = {
        w = 1;
      };
      q = {
        w = 2;
      };
      r = {
        w = 3;
      };
    };
  };
  latticeFor = {
    lattices = lib.genAttrs [ "p" "q" ] (_: {
      bottom = 0;
      join = a: b: if a > b then a else b;
      maxIter = 100;
    });
  };
  cyclicRecompute =
    acc: s: id:
    let
      w = (acc.nodeData id).w;
      deps = builtins.filter (d: s ? ${d}) (acc.edges id);
    in
    builtins.foldl' (m: d: if s.${d} > m then s.${d} else m) w deps;
in
{
  flake.tests.byte-parity = {
    # ── Plain values: every decision path, against a cold build of the same edited input. ──
    test-parity-override = {
      expr = parityHolds (valueArgs (ctx: override ctx "shared" { w = 100; }));
      expected = true;
    };
    test-parity-propagate = {
      expr = parityHolds (
        valueArgs (
          ctx:
          propagate (
            batch ctx [
              {
                id = "shared";
                newDecls = {
                  w = 100;
                };
              }
            ]
          )
        )
      );
      expected = true;
    };
    test-parity-propagate-eager = {
      expr = parityHolds (
        valueArgs (
          ctx:
          propagateEager ctx {
            shared = {
              w = 100;
            };
          }
        )
      );
      expected = true;
    };

    # ── Derivation identities as node values. ──
    test-parity-override-derivations = {
      expr = parityHolds (drvArgs (ctx: override ctx "shared" { w = 100; }));
      expected = true;
    };
    test-parity-propagate-eager-derivations = {
      expr = parityHolds (
        drvArgs (
          ctx:
          propagateEager ctx {
            shared = {
              w = 100;
            };
          }
        )
      );
      expected = true;
    };

    # THE DERIVATION FIXTURE IS REALLY DERIVATIONS. Without this the two cells above would pass
    # just as well over a fixture that produced ordinary strings, and would be claiming a coverage
    # they had not got.
    test-parity-derivation-fixture-yields-store-paths = {
      expr =
        let
          p = parity (drvArgs (ctx: override ctx "shared" { w = 100; }));
        in
        builtins.all (v: builtins.isString v && lib.hasPrefix builtins.storeDir v) (
          builtins.attrValues p.cold
        );
      expected = true;
    };

    # AND THE EDIT MOVES THEM. Otherwise the parity above would be the parity of two stores that
    # were going to agree whatever the plane decided: an edit invisible to the output cannot
    # distinguish a correct plane from one that reused everything.
    test-parity-derivation-edit-moves-identities = {
      expr =
        let
          base = build {
            accessor = fleetAcc;
            recompute = drvPathRecompute;
            inherit hashOf;
          };
          p = parity (drvArgs (ctx: override ctx "shared" { w = 100; }));
        in
        builtins.all (id: base.store.${id} != p.cold.${id}) [
          "shared"
          "h1"
          "h2"
          "h3"
        ];
      expected = true;
    };

    # ── The cyclic path: restabilize against a cold stratified build. ──
    test-parity-restabilize = {
      expr =
        let
          ctx = build {
            accessor = cyclicAcc;
            recompute = cyclicRecompute;
            inherit hashOf;
            fixpoint = latticeFor;
          };
          warm = restabilize ctx "r" { w = 30; };
          cold = build {
            accessor = changedAccessor cyclicAcc "r" { w = 30; };
            recompute = cyclicRecompute;
            inherit hashOf;
            fixpoint = latticeFor;
          };
        in
        observeStore warm.store == observeStore cold.store;
      expected = true;
    };

    # ── THE INSTRUMENT'S OWN LIVE CONTROL. ──
    # An instrument that reported parity for everything would pass every cell above. Here the warm
    # arm is compared against a cold evaluation of a DIFFERENT input — the unedited accessor — and
    # the comparison must come back FALSE. Same comparator, same fixtures, same run.
    test-parity-instrument-discriminates = {
      expr =
        let
          ctx = build {
            accessor = fleetAcc;
            recompute = valueRecompute;
            inherit hashOf;
          };
          warm = override ctx "shared" { w = 100; };
        in
        observeStore warm.store == observeStore ctx.store;
      expected = false;
    };

    # ── THE COMPARATOR'S DERIVATION BRANCH, armed directly (see the header for why not through
    # the plane). Both directions, so a comparator that answered "equal" to everything and one
    # that answered "unequal" to everything both fail. ──
    test-comparator-reads-drvpath-not-value = {
      expr =
        let
          d = mkDrv "gen-memo-parity-control" [ ] 1;
        in
        {
          branchFired = observe d == d.drvPath;
          isNotTheRecord = observe d != d;
          same =
            observe (mkDrv "gen-memo-parity-control" [ ] 1) == observe (mkDrv "gen-memo-parity-control" [ ] 1);
          different =
            observe (mkDrv "gen-memo-parity-control" [ ] 1) == observe (mkDrv "gen-memo-parity-control" [ ] 2);
          fallsThroughForPlainValues = observe 41 == 41;
        };
      expected = {
        branchFired = true;
        isNotTheRecord = true;
        same = true;
        different = false;
        fallsThroughForPlainValues = true;
      };
    };
  };
}
