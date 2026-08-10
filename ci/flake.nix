{
  inputs = {
    gen.url = "github:sini/gen";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use — including, here, to run the purity scan itself. It enters ONLY in ci/,
    # never as a `lib/` dep: the library (../lib) is nixpkgs-lib-free, which ci/tests/purity.nix
    # enforces. gen-memo itself takes no inputs, so `gen` and nixpkgs are the whole pin set.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, ... }:
    let
      genMemo = import ../lib;
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-memo";
      testModules = ./tests;
      specialArgs = { inherit genMemo; };
    };
}
