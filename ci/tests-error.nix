# THE SECOND TEST OUTPUT — cells whose subject is an ERROR, and the runner that reads them.
#
# Same structural reason as the pattern this mirrors (gen-graph, gen-scope, gen-merge, gen-link,
# gen-resolve's own `ci/tests-error.nix`): `gen-harness.lib.mkCi` builds `checks.default` from a
# homegrown asserter that forces every `t.expr` UNCONDITIONALLY over `config.flake.tests` and
# nothing else, so a cell whose `expr` ABORTS crashes that batch gate rather than failing it. A
# cell asserting an error is the clearest such cell. Hosting it on `flake.testsError` — via
# `extraModules` in `ci/flake.nix`, outside `testModules`, structurally rather than by a filename
# convention — keeps it live on the nix-unit path while staying out of `checks.default`'s
# quantifier.
#
#   nix-unit --flake ./ci#tests        # the suite (den-hoag-4xqpg does not touch this)
#   nix-unit --flake ./ci#testsError   # this cell
#
# ── THE MEASUREMENT THIS FILE CARRIES (den-hoag-4xqpg) ─────────────────────────────────────────
# `ci/tests/compose-parity.nix`'s comparator (`dropFns`) is cycle-aware at exactly one carrier
# shape: `isCycleCarrier v = builtins.isAttrs v && v ? _type && v._type == "option-type"`. That
# suite's own fixture demonstrates the guard firing on an OPTION-TYPE self-cycle (a completed
# type's `functor.type` is the type itself) and documents, out of suite, that the identical walk
# WITHOUT the carrier check aborts uncatchably on that same cycle. Left unmeasured: a cycle whose
# carrier is NOT tagged `_type == "option-type"` — the guard's `isCycleCarrier` predicate does not
# recognize it, so `seen` is never extended for it, and the walk should recurse forever on exactly
# the class of value the guard was not written to catch.
#
# `plainCycle` below is that value, injected through a `types.raw` leaf exactly as
# `compose-parity.nix`'s `hooks.ty` injects the option-type object — the fixture methodology this
# suite already established for "how a self-referential value gets into a resolved config" — and
# then run through the REAL `successor` compose (this file's own `subject`, not
# `compose-parity.nix`'s arms: mixing a value that aborts the walk into `armWarm`/`armCold` would
# take down every cell in that suite that calls `image`). The measured answer is DEFINITE: it
# aborts, uncaught, with the same "stack overflow; max-call-depth exceeded" the out-of-suite
# option-type reading names — confirmed live below, anchored at both ends, with a live control
# that the fixture is genuinely self-referential before anything walks it, and hand-verified
# match discrimination (see the measurement cell's own comment). This is a DEFECT reading, not a
# design act: it says what the comparator is not built to do, and does not attempt to widen
# `isCycleCarrier` — see den-hoag-4xqpg's own body for why that stays out of scope here.
#
# ★ A THIRD COPY, NAMED AS ONE. `dropFns`'s walk is a hand-written instance of the walk gen-flake
# ships at `lib/diff.nix:116-159`, already carried as a known weakness by `compose-parity.nix`'s
# own header (owner-ruled CARRIED, 2026-08-25) with the rider that "new fixtures must not add
# further UNNAMED copies" (den-hoag-4xqpg body). `walkCopy` below is `isCycleCarrier`+`walk` from
# `compose-parity.nix:57-98`, reproduced rather than imported because neither is exported from that
# file's `let`. Counting the shipped original as copy one and `compose-parity.nix`'s own as copy
# two, `walkCopy` is copy three; a drift between any of the three is a drift none of them can see,
# and nothing here should be read as closing that gap.
{
  lib,
  genMerge,
  genHub,
  genMemo,
  genInputs,
  ...
}:
let
  inherit (genMerge) types mkOption;

  # ── the comparator, copy three of the walk (see the header above) ──────────────────────────────
  walkCopy =
    let
      isCycleCarrier = v: builtins.isAttrs v && v ? _type && v._type == "option-type";
      carrierIndex =
        seen: x:
        let
          n = builtins.length seen;
          scan =
            i:
            if i >= n then
              null
            else if builtins.elemAt seen i == x then
              i
            else
              scan (i + 1);
        in
        scan 0;
      walk =
        seen: x:
        if builtins.isFunction x then
          null
        else if builtins.isList x then
          map (walk seen) x
        else if builtins.isAttrs x then
          (
            if isCycleCarrier x then
              let
                revisit = carrierIndex seen x;
              in
              if revisit != null then
                "<cycle:${toString revisit}>"
              else
                builtins.mapAttrs (_: walk ([ x ] ++ seen)) x
            else
              builtins.mapAttrs (_: walk seen) x
          )
        else
          x;
    in
    walk [ ];

  # ── the fixture: a non-option-type self-cycle, injected the way hooks.ty injects the
  # option-type one — a raw leaf carrying a hand-built value ──────────────────────────────────────
  plainCycle =
    let
      self = {
        tag = "plain-cycle";
        ref = self;
      };
    in
    self;

  decls = {
    options.leaf = mkOption {
      type = types.raw;
      default = null;
    };
  };

  successor = import "${genHub}/lib/compose.nix" {
    engine = genMerge;
    inherit (genMemo) warmAdmits warmTrace;
  };

  subject = successor.compose {
    modules = [
      decls
      { config.leaf = plainCycle; }
    ];
  };
in
{
  options.flake.testsError = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites whose cells' `expr` CAN ABORT: { suite.test = { expr; expected | expectedError; }; }. Read by `nix-unit --flake ./ci#testsError`; deliberately outside `flake.tests`, which the batch asserter forces every `expr` of and would crash on rather than fail.";
  };

  config = {
    flake.testsError.non-option-cycle = {
      # LIVE CONTROL — the fixture is genuinely self-referential before anything walks it. Nix's
      # `==` on attrsets short-circuits on pointer identity, so this reads cheaply rather than
      # forcing the same unbounded descent the measurement cell below is about.
      test-control-fixture-is-a-genuine-self-reference = {
        expr = {
          selfReferential = subject.values.leaf.ref == subject.values.leaf;
          tag = subject.values.leaf.tag;
        };
        expected = {
          selfReferential = true;
          tag = "plain-cycle";
        };
      };
      # THE MEASUREMENT. `isCycleCarrier` never matches this carrier, so `seen` is never extended
      # for it and the walk cannot terminate on it — this asserts that abort, anchored at both
      # ends. Match discrimination (wrong `type`, wrong `msg`) was checked by hand against this
      # exact cell before landing — both redden — rather than as a permanent cell, because the
      # only way to build one here is `tryEval` over the same aborting `expr`, and the abort
      # propagates THROUGH `tryEval` uncaught (that is the finding this cell states): a "wrong
      # type" cell built that way does not read false, it aborts the same way and proves nothing.
      test-nonoption-type-cycle-aborts-uncaught = {
        expr = builtins.toJSON (walkCopy subject.values);
        expectedError = {
          type = "Error";
          msg = "^stack overflow; max-call-depth exceeded$";
        };
      };
    };

    perSystem =
      { pkgs, system, ... }:
      {
        pre-commit.settings.hooks.ci-error = {
          enable = true;
          name = "ci-error";
          description = "Run nix-unit error-assertion tests";
          entry = "${
            pkgs.writeShellApplication {
              name = "gen-memo-ci-nix-unit-error";
              runtimeInputs = [ genInputs.nix-unit.packages.${system}.default ];
              text = ''
                exec nix-unit --flake ./ci#testsError "$@"
              '';
            }
          }/bin/gen-memo-ci-nix-unit-error";
          files = "\\.nix$";
          pass_filenames = false;
        };
      };
  };
}
