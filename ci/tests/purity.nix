# Purity invariant (gen-prelude design §5): gen-memo must import NO `nixpkgs.lib`. This pins
# "pure" as a checked property, not an aspiration — a stray `lib.foo` / `lib.types` /
# `evalModules` / nixpkgs input creeping into the library source fails CI.
#
# The plane decides reuse and never evaluates, so the module-system tokens below are the sharper
# half of the scan here: an `evalModules` or `mkOption` appearing in this library would be the
# plane doing the evaluator's work.
#
# Scope: lib/**.nix + the root flake.nix + default.nix (the library and its flake). NOT ci/ — the
# test harness legitimately uses nixpkgs.lib, including to run this scan.
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Comment-stripped source: drop everything from the first `#` on each line. Safe here because
  # `#` appears only in comments across these files (no `#` in string literals); documentation may
  # freely mention forbidden tokens without tripping the invariant.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  nixFiles = lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir));
  sources =
    map (name: {
      inherit name;
      code = stripComments (builtins.readFile (libDir + "/${name}"));
    }) nixFiles
    ++ [
      {
        name = "flake.nix";
        code = stripComments (builtins.readFile ../../flake.nix);
      }
      {
        name = "default.nix";
        code = stripComments (builtins.readFile ../../default.nix);
      }
    ];

  # Tokens that signal a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  violations = lib.concatMap (
    src:
    map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
  ) sources;

  # Positive control for the scan itself: the same predicate, same run, over a string that DOES
  # contain a forbidden token. An empty `violations` above is only evidence if this is non-empty —
  # otherwise a broken `hasInfix` or an empty `sources` would report clean.
  controlViolations = lib.filter (
    tok: genPrelude.hasInfix tok "let x = evalModules { }; in x"
  ) forbidden;
in
{
  flake.tests.purity = {
    test-library-source-is-nixpkgs-lib-free = {
      expr = violations;
      expected = [ ];
    };

    # The scan reaches real files with real content. A vacuous `sources` — an empty lib/, a
    # readDir that found nothing — would report the invariant clean without testing it, so the
    # non-emptiness is asserted rather than assumed. Stable as the library grows.
    test-scan-reads-non-empty-sources = {
      expr = sources != [ ] && lib.all (s: s.code != "") sources;
      expected = true;
    };

    test-forbidden-token-scan-is-live = {
      expr = controlViolations;
      expected = [ "evalModules" ];
    };
  };
}
