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
    # 31 exports. The first 24 arrived with the rebuilder content, unchanged in name — that
    # migration moved content, not surface. `hashGuarded` / `hashEq` / `hashMoved` are deliberately
    # NOT here (see lib/hash.nix), and the shadowed `override` definition that the retiring
    # library's fold left unreachable did not travel — the reached one did, so the count was
    # unchanged either way.
    #
    # The three `warm*` names are the second migration, and TWO OF THEM ARE RENAMES rather than the
    # names their own library published. `override` was already taken here, by the store's fused
    # `propagate ∘ applyDelta` — a different operation on a different object — and the module fold
    # REFUSES a collision rather than resolving it by list position, so a name had to give. The
    # prefix says which layer the fold operates at, which the bare name did not:
    #
    #   gen-resolve `override`     → `warmOverride`
    #   gen-resolve `warmResolve`  → `warmResolve`   (unchanged)
    #   —                          → `warmDecision`  (new: the DECISION, apart from the fold)
    #
    # `warmDecision` is the one addition. The fold's reuse decision was a local binding inside it
    # and had no name on any surface; the interface the whole design rests on is two total functions
    # and no values, and a surface that offers only the fold leaves that type unobservable.
    #
    # `whyFor` / `whyNotFor` are the two after those: the amortized duals of the provenance queries,
    # curried on the change so a caller asking many ids binds the cone once. They are a WIDENING and
    # not a replacement — `why` / `whyNot` keep their per-call contract, which is why the surface
    # grows by two rather than changing under two existing names.
    #
    # `warmAdmits` / `warmTrace` are the third migration, and ONE OF THEM IS A RENAME for the same
    # reason two of the first three were. The content arrived carrying a `trace` built from its
    # evaluator's `warmDecision`, and that name was already taken here by the plane's OWN decision —
    # two total functions over a declared node graph, which is a different record about a different
    # object at a different granularity. The fold refuses a collision rather than resolving it by
    # list position, so the observation took a name that cannot be read as the decision's synonym:
    #
    #   the observed evaluator's `warmDecision` → `warmTrace`
    #   —                                       → `warmAdmits`  (new: the admission test, apart
    #                                                            from the record it gates)
    #
    # `warmAdmits` is the addition, and it is the same split `warmDecision` was: the test lived
    # inside its caller's `override` handle with no name on any surface, and a surface offering only
    # the record leaves the predicate that decides whether there is one unobservable.
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
        "warmAdmits"
        "warmDecision"
        "warmOverride"
        "warmResolve"
        "warmTrace"
        "why"
        "whyFor"
        "whyNot"
        "whyNotFor"
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
          project = null;
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
