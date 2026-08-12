# The surface pin.
#
# WHAT THIS SUITE ACTUALLY CHECKS, and what it only asks for. Be precise about the difference —
# the obligation below is half machine-checked and half convention, and reading it as one thing
# would leave the documentation claiming a gate that does not exist.
#
#   CHECKED, here, by this cell: the export surface cannot change without someone editing this
#   file. A widening — or a silent loss — lands as a failing test. That much is a gate and it
#   holds.
#
#   NOT CHECKED, but co-located: that AGENTS.md's Exports section was updated in the same change.
#   No cell asserts it. It is at least in this repository, in the same commit, visible in one diff.
#
#   NOT CHECKABLE FROM HERE AT ALL: that the canonical reference spec was updated. It lives in
#   another repository (papers/den-architecture/gen-specs/gen-memo/REFERENCE.md), on its own
#   history, and that repository has no CI — no `.github` directory exists in it. A Nix test in
#   gen-memo can observe this library's export surface; it cannot observe a file over there, and
#   nothing over there will observe this. That half is convention, held by whoever reviews.
#
# So: this suite prevents a SILENT change of the surface. It does not, and cannot, prevent the
# documentation from falling behind it.
{
  genMemo,
  prelude,
  graph,
  ...
}:
let
  inherit (import ../../lib/merge.nix { inherit prelude; }) mergeExports;
in
{
  flake.tests.surface = {
    # The 24 exports the plane's content arrived with — the same set the retiring library
    # published, which is the point: the migration moved content, not surface. `hashGuarded` /
    # `hashEq` / `hashMoved` are deliberately NOT here (see lib/hash.nix), and the shadowed
    # `override` definition that the retiring library's fold left unreachable did not travel —
    # the reached one did, so the count is unchanged either way.
    test-lib-exports-the-plane = {
      expr = builtins.attrNames genMemo;
      expected = [
        "affected"
        "affectedSet"
        "applyDelta"
        "applyEdgeDelta"
        "batch"
        "build"
        "dirtySet"
        "earlyCutoff"
        "force"
        "forceCtx"
        "impactOf"
        "mkAccessor"
        "needsEval"
        "override"
        "propagate"
        "propagateEager"
        "restabilize"
        "retract"
        "runScc"
        "support"
        "supportDirect"
        "verify"
        "why"
        "whyNot"
      ];
    };

    # The internal hash guards are reachable by direct import and NOT through the library value.
    # Stated as a cell because "we did not add it to the list" is a fact about one file, while
    # "it is not on the surface" is the property, and a later fold that swept `lib/*.nix` would
    # satisfy the first and break the second.
    test-hash-guards-are-not-exported = {
      expr = builtins.attrNames (
        builtins.intersectAttrs {
          hashGuarded = null;
          hashEq = null;
          hashMoved = null;
        } genMemo
      );
      expected = [ ];
    };

    # The module fold REFUSES a duplicate export rather than resolving it by list position.
    # Both arms of the same rule in one run: a colliding pair must throw, and a disjoint pair
    # must merge. Without the second arm a rule that threw on everything would look correct;
    # without the first, one that never checks would.
    test-duplicate-export-refuses = {
      expr = (builtins.tryEval (mergeExports "probe" { override = 1; } { override = 2; })).success;
      expected = false;
    };

    test-disjoint-exports-merge = {
      expr = mergeExports "probe" { a = 1; } { b = 2; };
      expected = {
        a = 1;
        b = 2;
      };
    };

    # The standalone (non-flake) root entry and the `lib/` entry are one surface. The two
    # diverging is the classic gen root-file drift. Compared on NAMES rather than on values:
    # every export here is a function, and Nix compares two functions as unequal even when they
    # are the same definition, so a value comparison would fail on a correct library.
    test-standalone-entry-matches-lib = {
      expr = builtins.attrNames (import ../.. { inherit prelude graph; });
      expected = builtins.attrNames genMemo;
    };
  };
}
