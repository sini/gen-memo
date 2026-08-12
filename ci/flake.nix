{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
    # gen-scope enters HERE AND ONLY HERE. The library takes no evaluator dependency — the plane
    # decides for an evaluator it is HANDED — but a fold that is handed one can only be exercised by
    # handing it one, and a stub evaluator would make the warm suites an oracle for the stub. The
    # asymmetry is nixpkgs's below: a test-runner input is not a library input, and ../lib is
    # checked to be free of both.
    gen-scope.url = "github:sini/gen-scope";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use — including, here, to run the purity scan itself. It enters ONLY in ci/,
    # never as a `lib/` dep: the library (../lib) is nixpkgs-lib-free, which ci/tests/purity.nix
    # enforces.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      gen-graph,
      gen-scope,
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
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-memo";
      testModules = ./tests;
      specialArgs = {
        inherit
          genMemo
          graph
          prelude
          engine
          ;
        genScope = gen-scope.lib;
      };
    };
}
