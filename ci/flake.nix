{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
    # gen-scope enters HERE AND ONLY HERE. The library takes no evaluator dependency — the plane
    # decides for an evaluator it is HANDED — but a fold that is handed one can only be exercised by
    # handing it one, and a stub evaluator would make the warm suites an oracle for the stub. The
    # asymmetry is nixpkgs's below: a test-runner input is not a library input, and ../lib is
    # checked to be free of both.
    gen-scope.url = "github:sini/gen-scope";
    # gen-merge enters HERE AND ONLY HERE, on gen-scope's ground and for the same reason. The two
    # functions in `lib/warmTrace.nix` decide FOR an evaluator they are handed and name none, so the
    # only way to exercise them against the caller they were migrated from is to hand them that
    # caller's evaluator. `ci/tests/compose-parity.nix` is the byte-parity oracle of that migration
    # and its subject is a compose-shaped module tree, which is gen-merge's to produce; a stub would
    # make the oracle an oracle for the stub. The asymmetry is nixpkgs's below — a test-runner input
    # is not a library input — and `ci/tests/purity.nix` scans `../lib` and enforces it.
    gen-merge.url = "github:sini/gen-merge";
    # The gen HUB SOURCE — `flake = false`, and that is R1's discipline rather than thrift. The
    # successor compose (the construct `ci/tests/compose-parity.nix` evaluates) lives at the hub,
    # `lib/compose.nix`, parameterised on an engine and the plane's two decision functions. The
    # suite imports the FILE and applies THIS lock's gen-merge and ../lib to it — a full-flake hub
    # input would carry a second gen-merge pin, and an oracle with two engine revisions in one run
    # is not a reading. The pin must be at or past the hub revision that carries lib/compose.nix.
    gen.url = "github:sini/gen";
    gen.flake = false;
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use — including, here, to run the purity scan itself. It enters ONLY in ci/,
    # never as a `lib/` dep: the library (../lib) is nixpkgs-lib-free, which ci/tests/purity.nix
    # enforces.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      gen-prelude,
      gen-graph,
      gen-scope,
      gen-merge,
      gen,
      ...
    }:
    let
      prelude = import "${gen-prelude}/lib";
      graph = gen-graph.lib;
      genMemo = import ../lib { inherit prelude graph; };

      # THE ENGINE, ASSEMBLED HERE BECAUSE THE HARNESS IS THE CALLER. The plane populates no
      # store of its own — it hands a domain, a base and a decision to an engine and lets the
      # engine produce the values — so every entry point that reaches a store takes one. A test
      # is a caller like any other and brings the evaluation environment it has: `evalWarm` is
      # the real evaluator, and the reference scheduler stands in on the cold paths, which have
      # no gen-scope entry to route through yet. Both live outside `../lib`, which is the point.
      engine = (import ../reference/schedule.nix { inherit prelude; }) // {
        inherit (gen-scope.lib) evalWarm;
      };

      # Fixture constructors. They live outside ./tests so the harness does not collect them as a
      # test module, and they reach every module through specialArgs rather than through an import
      # repeated in each one.
      fx = import ./fixtures.nix { inherit graph; };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-memo";
      testModules = ./tests;
      specialArgs = {
        inherit
          genMemo
          graph
          prelude
          engine
          fx
          ;
        genScope = gen-scope.lib;
        genMerge = gen-merge.lib;
        # The hub SOURCE (flake = false above): compose-parity imports the successor compose from
        # it and binds this lock's engine to it.
        genHub = gen;
      };
      # `testModules` is the batch asserter's own quantifier (`gen-harness/flakeModule.nix`'s
      # `flake.tests`), which forces every cell's `expr` unconditionally — a cell that ABORTS
      # belongs outside it by construction. `ci/tests-error.nix` is den-hoag-4xqpg's non-option-
      # type cycle measurement, exactly that kind of cell; the ecosystem-standard split
      # (gen-graph, gen-scope, gen-merge, gen-link, gen-resolve all carry the identical pattern)
      # puts it here rather than under ./tests.
      extraModules = [ ./tests-error.nix ];
    };
}
