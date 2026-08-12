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

  # Labels are repo-root-relative rather than bare basenames. `readDir libDir` yields
  # `default.nix` for `lib/default.nix`, which is the SAME string as the root `default.nix`
  # appended below — so an unqualified label makes a violation in the library indistinguishable
  # from one in the root entry, and the scan names a file that cannot be located.
  nixFiles = lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir));
  sources =
    map (name: {
      name = "lib/${name}";
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

  # THE PLANE BINDS NO STORE FIX, scanned over the same comment-stripped sources. A
  # self-referential store over the node set, passed into the caller's node computation, is what
  # makes a construct an evaluator rather than a decision layer — so the plane hands a domain, a
  # base and a decision to an engine and the engine binds the knot.
  #
  # ★ WHAT THIS CELL CANNOT SEE, said here so its green is not read as wider than it is: it is a
  # TOKEN scan, and a store fix has other spellings. A fold threading its own accumulator of
  # resolved outputs across a traversal it drives is the same thing by a different construction,
  # and two of those remain in this library — the condensation solve in `build.nix`, and the
  # rank-ordered drain in `eager.nix`, with `runScc` beneath the first. This scan is a tripwire
  # against the knot coming back in the shape it left in, not a proof that none is present.
  knotToken = "prelude.fix";
  knotSites = map (src: src.name) (lib.filter (src: genPrelude.hasInfix knotToken src.code) sources);

  # And its own live control: the SAME token and the SAME predicate over the reference scheduler,
  # which is where the knot now lives. Without this, a typo in the token would report the plane
  # clean of a construct the scan could never have matched.
  knotControlFires = genPrelude.hasInfix knotToken (
    stripComments (builtins.readFile ../../reference/schedule.nix)
  );
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

    test-plane-binds-no-store-fix = {
      expr = knotSites;
      expected = [ ];
    };

    test-store-fix-scan-is-live = {
      expr = knotControlFires;
      expected = true;
    };
  };
}
