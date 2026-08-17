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
  # ★ WHAT THIS TOKEN ARM CANNOT SEE, said here so its green is not read as wider than it is.
  # A store fix has other spellings, and the residue is FOUR sites, not the two an earlier form of
  # this comment named. A fold threading its own accumulator of resolved outputs across a traversal
  # it drives is the same construct by a different construction, and all four are in this library
  # (coordinates at the rev that added this cell):
  #
  #   1. `build.nix:155-190`        — the bottom-up condensation solve
  #   2. `restabilize.nix:134-139`  — `runScc`'s ascent, beneath the first
  #   3. `restabilize.nix:240-271`  — `restabilize`'s OWN cone solve, a separate fold from 2
  #   4. `eager.nix:71-75`          — the rank-ordered eager drain
  #
  # This scan is a tripwire against the knot coming back in the shape it left in, not a proof that
  # none is present.
  knotToken = "prelude.fix";
  knotSites = map (src: src.name) (lib.filter (src: genPrelude.hasInfix knotToken src.code) sources);

  # And its own live control: the SAME token and the SAME predicate over the reference scheduler,
  # which is where the knot now lives. Without this, a typo in the token would report the plane
  # clean of a construct the scan could never have matched.
  knotControlFires = genPrelude.hasInfix knotToken (
    stripComments (builtins.readFile ../../reference/schedule.nix)
  );

  # ★ THE IMPORT ROUTE, which the token arm above does NOT close and which is the likelier way the
  # knot comes back. A `lib/` file that writes `import ../reference/schedule.nix` and calls
  # `schedule` itself has the knot back with no `prelude.fix` token anywhere in `lib/` — measured,
  # that plant leaves the token arm entirely green. Reaching the reference scheduler from inside
  # the plane is what would make it the plane's; being handed it at the call is what makes it the
  # caller's. So the path is scanned as well.
  importToken = "reference/";
  importSites = map (src: src.name) (
    lib.filter (src: genPrelude.hasInfix importToken src.code) sources
  );

  # Its live control is an import the library REALLY MAKES, so the predicate is shown to match an
  # import path in this corpus rather than merely to return empty. `./hash.nix` is imported
  # directly by the files that need the guards, which is the same syntactic shape a smuggled
  # `../reference/schedule.nix` would take.
  importControlSites = map (src: src.name) (
    lib.filter (src: genPrelude.hasInfix "./hash.nix" src.code) sources
  );
in
{
  flake.tests.purity = {
    # This `[ ]` is not self-supporting: its subject is read from disk, so it is non-vacuous
    # exactly in composition with the subject-pinning cell asserted over the same `sources` value —
    # `test-scan-subject-is-the-library-tree` below, which pins WHICH files the scan reads.
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

    # ★ THE SCAN'S SUBJECT, MEMBERSHIP HALF — the literal label list, asserted by identity rather
    # than by count. Disconnection is an identity defect and non-emptiness is a cardinality
    # predicate, so the two do not meet and the floor above cannot stand in for this: measured
    # against the suite WITHOUT this cell, `nixFiles` cut to just the seven labels the import-route
    # control names leaves every other cell here green while a live `lib.types` tether sits in one
    # of the seven files that left the scan. This cell is the one that reds that cut.
    #
    # It is ONE HALF of the pair every absence cell in this file composes with. An absence cell
    # asserts `expr == [ ]`, and a scan of nothing produces nothing — so this is what makes
    # `test-library-source-is-nixpkgs-lib-free`'s `[ ]`, `test-plane-binds-no-store-fix`'s `[ ]`
    # and `test-plane-does-not-import-the-reference-scheduler`'s `[ ]` evidence rather than
    # artefacts of an empty subject. Each of those is satisfied by a degenerate subject alone.
    #
    # WHAT IT IS SILENT ON: content. A `read` handing every entry one fixed string satisfies this
    # cell exactly — names are all it pins, and the other half of the pair is what pins those.
    #
    # `reference/schedule.nix` is NOT a member, by construction rather than by omission: it is read
    # by the store-fix control below, which is a different subject, not by the library scan.
    # Joining it would move this list to 17 and widen the library cell's subject past `lib/**` plus
    # the two roots, which is more than that cell claims.
    test-scan-subject-is-the-library-tree = {
      expr = map (s: s.name) sources;
      expected = [
        "lib/affected.nix"
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/default.nix"
        "lib/dirtySet.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/hash.nix"
        "lib/merge.nix"
        "lib/provenance.nix"
        "lib/restabilize.nix"
        "lib/strategies.nix"
        "lib/structural.nix"
        "lib/warm.nix"
        "flake.nix"
        "default.nix"
      ];
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

    # The plane does not REACH the reference scheduler; it is handed one. Closing the import route
    # the token arm above leaves open.
    test-plane-does-not-import-the-reference-scheduler = {
      expr = importSites;
      expected = [ ];
    };

    # The import predicate matches a real import in this corpus, so the empty result above is a
    # finding rather than a predicate that could never have fired. Asserted as the exact file list
    # rather than as non-emptiness: a new direct importer of the guards should be seen, not absorbed.
    test-import-route-scan-is-live = {
      expr = importControlSites;
      expected = [
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/restabilize.nix"
        "lib/strategies.nix"
        "lib/structural.nix"
      ];
    };
  };
}
