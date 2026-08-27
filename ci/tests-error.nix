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
# ── THE MEASUREMENT THIS FILE CARRIED, AND THE FIX LANDED IN ITS PLACE ─────────────────────────
# `ci/tests/compose-parity.nix`'s comparator (`dropFns`) WAS cycle-aware at exactly one carrier
# shape: `isCycleCarrier v = builtins.isAttrs v && v ? _type && v._type == "option-type"`. That
# suite's own fixture demonstrated the guard firing on an OPTION-TYPE self-cycle (a completed
# type's `functor.type` is the type itself); den-hoag-4xqpg then measured that the identical walk
# WITHOUT that tag aborts uncatchably on a cycle whose carrier is untagged — `plainCycle` below, a
# plain self-referential attrset injected through a `types.raw` leaf exactly as
# `compose-parity.nix`'s `hooks.ty` injects the option-type object, the fixture methodology this
# suite already established for "how a self-referential value gets into a resolved config", run
# through the REAL `successor` compose (this file's own `subject`, not `compose-parity.nix`'s arms:
# mixing a value that could abort the walk into `armWarm`/`armCold` would take down every cell in
# that suite that calls `image`). `isCycleCarrier`'s tag was never a completeness claim — it was
# the one shape the guard had met. den-hoag-4xqpg deliberately left widening it out of scope; that
# generalization is den-hoag-memo-cycle-guard-shape-wt4b9, landed here: `dropFns`/`walkCopy` now
# push EVERY attrs node onto `seen` and test ancestor-path membership for all of them, not only the
# ones tagged `_type == "option-type"`. `builtins.isAttrs x` already decided which nodes reach the
# check; the tag was an arbitrary narrowing of that same domain, so removing it extends the
# existing operation rather than adding a new one. `plainCycle` now cuts the same way the
# option-type fixture does — the measurement cell below asserts the `<cycle:0>` marker in place of
# the abort, with the live self-reference control kept unchanged as the fixture-integrity check.
#
# ★ A THIRD COPY, NAMED AS ONE. `dropFns`'s walk is a hand-written instance of the walk gen-flake
# ships at `lib/diff.nix:116-159`, already carried as a known weakness by `compose-parity.nix`'s
# own header (owner-ruled CARRIED, 2026-08-25) with the rider that "new fixtures must not add
# further UNNAMED copies" (den-hoag-4xqpg body). `walkCopy` below is `carrierIndex`+`walk` from
# `compose-parity.nix:57-95`, reproduced rather than imported because neither is exported from that
# file's `let`. Counting the shipped original as copy one and `compose-parity.nix`'s own as copy
# two, `walkCopy` is copy three; a drift between any of the three is a drift none of them can see,
# and nothing here should be read as closing that gap. Both local copies carry the SAME
# generalization in this change, so they do not drift from EACH OTHER on this axis.
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
  # Cycle-aware at EVERY attrs node on the path (den-hoag-memo-cycle-guard-shape-wt4b9), not only
  # `_type == "option-type"` — see the header for why the tag was a narrowing, not a boundary.
  walkCopy =
    let
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
          let
            revisit = carrierIndex seen x;
          in
          if revisit != null then
            "<cycle:${toString revisit}>"
          else
            builtins.mapAttrs (_: walk ([ x ] ++ seen)) x
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
      # THE MEASUREMENT, FLIPPED (den-hoag-memo-cycle-guard-shape-wt4b9). `seen` now collects
      # EVERY attrs node on the path, not only ones tagged `_type == "option-type"`, so `self` is
      # pushed onto it the first time it is walked (as `subject.values.leaf`) and the revisit
      # through `self.ref` is caught: index 0, the innermost (and only) attrs ancestor. The walk
      # completes and cuts the cycle exactly as the option-type fixture does, instead of aborting.
      test-nonoption-type-cycle-cuts = {
        expr = builtins.toJSON (walkCopy subject.values);
        expected = builtins.toJSON {
          leaf = {
            tag = "plain-cycle";
            ref = "<cycle:0>";
          };
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
