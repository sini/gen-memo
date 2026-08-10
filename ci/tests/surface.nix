# The shell tripwire.
#
# gen-memo ships with an EMPTY export surface on purpose: the plane's exports may not be written
# ahead of the spec that settles what it reads from the evaluator, because an export written first
# would fix that interface by accident. This suite makes that a checked fact rather than a note, so
# the first export lands as a failing test — the author is then obliged to state the surface in
# AGENTS.md and REFERENCE.md in the same change, and a silent widening cannot happen.
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
