# The shell tripwire.
#
# gen-memo ships with an EMPTY export surface on purpose: the plane's exports may not be written
# ahead of the spec that settles what it reads from the evaluator, because an export written first
# would fix that interface by accident.
#
# WHAT THIS SUITE ACTUALLY CHECKS, and what it only asks for. Be precise about the difference —
# the obligation below is half machine-checked and half convention, and reading it as one thing
# would leave the documentation claiming a gate that does not exist.
#
#   CHECKED, here, by this cell: an export cannot appear without someone editing this file. The
#   first export lands as a failing test. That much is a gate and it holds.
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
# So: this suite prevents a SILENT WIDENING of the surface. It does not, and cannot, prevent the
# documentation from falling behind it.
#
# When content lands: replace the empty expectation with the real surface, not the suite.
{ genMemo, ... }:
{
  flake.tests.surface = {
    test-lib-exports-nothing = {
      expr = builtins.attrNames genMemo;
      expected = [ ];
    };

    # The standalone (non-flake) root entry and the `lib/` entry are one value. The two entries
    # diverging is the classic gen root-file drift; asserting equality keeps them one surface as
    # the library grows past the zero-dependency shape.
    test-standalone-entry-matches-lib = {
      expr = import ../.. == import ../../lib;
      expected = true;
    };
  };
}
