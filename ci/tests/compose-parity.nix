# BYTE-PARITY OF THE COMPOSE MIGRATION — ADR-0008's definitional oracle, instanced for the two
# functions `lib/warmTrace.nix` received from gen-flake's `composeAt`.
#
# THE SUBJECT IS THE DECISION CROSSING, NOT THE PLANE'S OWN FOLD. `ci/tests/byte-parity.nix` and
# `ci/tests/warm-parity.nix` already carry the plane's defining property over the memo fold. Neither
# can see this one: the question here is whether routing a caller's warm-fire decision through
# `warmAdmits` — and its published record through `warmTrace` — leaves that caller's own output
# byte-identical to the cold evaluation of the same input. That is a property of the CALLER's
# evaluation, so the caller's evaluator has to be present, which is why `ci/flake.nix` takes
# gen-merge for this file and `../lib` still declares neither it nor an evaluator of any kind.
#
# THE CALLER IS WRITTEN HERE, IN THE SHAPE THE MIGRATION LEAVES IT. `composeAt` below is the part of
# gen-flake's compose that does NOT cross — the `evalModuleTree` invocation, the warm-knob splice,
# the re-compose of merged args, and the recursion — with the two crossing parts replaced by calls
# into this library. It is deliberately the KERNEL and not a port: no tree loader, no `specialArgs`
# thread, no aspect registry, no host projection. Those belong to other rows of the same settlement
# and none of them is compared by this oracle, which reads `values` and `provenance` only. A reader
# should take this as the oracle's caller, never as the successor compose's declared surface — that
# surface does not exist yet and this file does not propose one.
#
# R1 — THE ENGINE REVISION IS PART OF THE ORACLE, and an unpinned run is not a reading. Both arms
# run at whatever `ci/flake.lock` pins for gen-merge, which is the whole of the pin: one lock, one
# revision, both arms, recorded with the result. The reason is not procedural. The overflow bracket
# this oracle's ancestor was written against moved once already, and it was only visible because the
# revisions had been recorded on both sides; the next such move will look exactly like that one did.
#
# ★ THE COMPARATOR IS A COPY, AND THAT IS A KNOWN, CARRIED WEAKNESS. `dropFns` below is a
# hand-written instance of the walk gen-flake ships at `lib/diff.nix:116-159` — a `let`-local inside
# `diff`'s lambda body, which no caller can name — mirrored in that repository's own tests at
# `ci/tests/compose.nix:289-332`. This file adds a further instance, so a drift between the shipped
# walk and the copies is a drift this suite cannot see, and nothing below should be read as closing
# that gap: no cell here puts the shipped walk's verdict and a copy's verdict on the same pair. The
# residue is owner-ruled as CARRIED (2026-08-25) rather than discharged, and it is stated at the
# comparator because that is where a reader meets it.
{
  genMemo,
  genMerge,
  ...
}:
let
  inherit (genMerge)
    evalModuleTree
    types
    mkOption
    mkForce
    ;

  # ── the comparator ─────────────────────────────────────────────────────────────────────────────
  # Functions are nulled rather than skipped, so a topology change still moves the bytes even though
  # the closures themselves cannot be compared — which is exactly the blindness the H1 control below
  # measures. The walk is cycle-aware at the option-type protocol marker: a completed type's
  # `functor.type` is the type itself, so an unguarded descent would not terminate.
  dropFns =
    let
      isCycleCarrier = v: builtins.isAttrs v && v ? _type && v._type == "option-type";
      # The revisited carrier's index among the carrier ancestors on the path, or null when the node
      # is not one of them. `seen` is nearest-ancestor-first, so 0 is the innermost.
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

  # Both halves, always. A values-only comparison passes while the provenance topology is corrupt,
  # and the two halves are sensitive to different corruptions — see the two RED controls, which are
  # separate cells for that reason.
  image = r: {
    values = builtins.toJSON (dropFns r.values);
    provenance = builtins.toJSON (dropFns r.provenance);
  };

  # Occurrences of a literal in an image. `builtins.split` returns the non-matching segments as
  # strings and each match's capture list as a LIST, so counting the lists counts the matches.
  countIn =
    needle: hay: builtins.length (builtins.filter builtins.isList (builtins.split needle hay));

  # ── the caller, with the two migrated decisions crossing into this library ─────────────────────
  # The warm knobs reach the engine ONLY on a fired warm override; a base compose and a refused one
  # pass neither, which is the engine's documented zero-behaviour-change default. `warmAdmits` is
  # handed the argument key its caller's warm splice is defined against — the plane holds no
  # evaluator's argument names, so the key arrives as a parameter.
  composeAt =
    {
      warmFrom ? null,
      editedModules ? [ ],
      traced ? false,
    }:
    args@{
      modules ? [ ],
    }:
    let
      warmKnobs = if warmFrom == null then { } else { inherit warmFrom editedModules; };
      result = evalModuleTree ({ inherit modules; } // warmKnobs);
      projection = {
        values = result.config;
        inherit (result) provenance;
        override =
          edits:
          composeAt
            (
              if genMemo.warmAdmits "modules" edits then
                {
                  warmFrom = result;
                  editedModules = edits.modules;
                  traced = true;
                }
              else
                { traced = true; }
            )
            (
              args
              // {
                modules = (args.modules or [ ]) ++ (edits.modules or [ ]);
              }
            );
      };
    in
    # The observation is spliced UNCONDITIONALLY — a result reached without an edit carries no
    # `trace` because the record says so, not because this branch says so.
    projection
    // genMemo.warmTrace {
      edited = traced;
      decision = result.warmDecision;
    };

  compose = composeAt { };

  # ── the migration fixture ──────────────────────────────────────────────────────────────────────
  # `hooks` is declared `attrsOf raw` and defined with a lambda. That is not decoration: H1's class
  # is the leaf that is a FUNCTION on both sides of a comparison, and a fixture that never carries
  # one cannot exhibit it. A resolved config carrying function-valued leaves as its ordinary shape is
  # what makes the blindness control below a measurement rather than a restatement of the hedge.
  decls = {
    options = {
      hosts = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              addr = mkOption { type = types.str; };
              role = mkOption {
                type = types.str;
                default = "worker";
              };
            };
          }
        );
        default = { };
      };
      hooks = mkOption {
        type = types.attrsOf types.raw;
        default = { };
      };
      fleet = {
        name = mkOption { type = types.str; };
        size = mkOption {
          type = types.int;
          default = 0;
        };
      };
    };
  };

  # Parameterised on the hook's closure ALONE — every other byte of the module list is shared, which
  # is what lets the H1 seed differ in the closure and in nothing else.
  #
  # ★ `hooks.ty` PUTS AN OPTION-TYPE OBJECT IN `values`, AND WITHOUT IT THIS ORACLE WOULD NOT
  # EXERCISE THE HALF OF THE COMPARATOR IT WAS CHOSEN FOR. A completed type's `functor.type` is the
  # type itself, so the resolved config carries a self-cycle. Measured on this fixture at the pinned
  # revision, out of suite because neither reading can be a cell: the SAME subject walked by an
  # otherwise identical walk WITHOUT the carrier seen-test aborts with
  # `stack overflow; max-call-depth exceeded` — and that abort propagates THROUGH `builtins.tryEval`
  # (verified in the same run against a `throw` and an `assert`, both of which it catches), so a cell
  # over the naive walk would abort the whole suite rather than redden in it. With the cut, the walk
  # completes and the cut is visible as `<cycle:N>` markers, which is what the in-suite control below
  # asserts. Before this definition existed the fixture produced ZERO markers on a 194-byte image:
  # the cycle cut could not fire, so an oracle green would have said nothing about the class.
  mkBase = hook: [
    decls
    {
      config.hosts.n1.addr = "10.0.1.1";
      config.hosts.n2.addr = "10.0.1.2";
      config.hooks.transform = hook;
      config.hooks.ty = types.listOf types.str;
      config.fleet.name = "prod";
      config.fleet.size = 2;
    }
  ];
  base = mkBase (x: x + 1);
  addN3 = {
    config.hosts.n3.addr = "10.0.1.3";
  };

  ovBase = compose { modules = base; };

  # ARM WARM — the override whose edit `warmAdmits` admits, so the engine splices.
  armWarm = ovBase.override { modules = [ addN3 ]; };
  # ARM COLD — the same fixture and the same revision with no warm context at all.
  armCold = compose { modules = base ++ [ addN3 ]; };

  # ── RED CONTROL 1 — the ordinary leaf ──────────────────────────────────────────────────────────
  ovDiffering = ovBase.override {
    modules = [ { config.hosts.n1.addr = mkForce "10.4.4.4"; } ];
  };

  # ── RED CONTROL — the provenance half, armed on its own ────────────────────────────────────────
  # MEASURED, and it is why this control exists as a separate seed: control 1's forced definition
  # sits at `hosts.n1.addr`, INSIDE a submodule, and this engine's provenance stops at the declared
  # leaf `hosts` — nested evaluations are a documented provenance boundary. Control 1 therefore moves
  # the `values` image and leaves the `provenance` image byte-identical, so on its own it arms one
  # half and certifies the other. This seed moves the second def count and the winning priority at a
  # TOP-LEVEL declared leaf, which is where this channel records anything at all.
  ovProvSeed = ovBase.override {
    modules = [ { config.fleet.size = mkForce 9; } ];
  };

  # ── RED CONTROL 2 — inside the comparator's own blind class (H1) ────────────────────────────────
  # Two composes differing ONLY in the closure a function-valued leaf resolves to. The module list is
  # otherwise byte-shared, so the def count, the priorities and the winners at every loc are equal by
  # construction and the provenance image cannot move for an unrelated reason. Both sides are
  # functions — a function↔data flip is a change the walk DOES catch and would test the wrong thing.
  #
  # ★ THE EXPECTED READING IS GREEN, AND GREEN IS THE REFUSAL BRANCH. Under a correct seed the
  # nulling is total: both leaves become `null`, both halves are byte-equal, and the comparison
  # reports no difference. That is the hedge firing exactly as the shipped walk describes it — "two
  # DIFFERENT functions both compare EQUAL after nulling" — so the outcome of this mandatory control
  # is that the byte-parity oracle does NOT discharge for function-valued content by this
  # comparator. A RED here is an INSTRUMENT FINDING, never a pass: it would mean the seed leaked —
  # a leaf that was not a function on both sides, or a provenance record that moved — and the cell
  # measured something other than the class. The two seed-integrity cells below exist so that a
  # green cannot be read without them.
  c2a = compose { modules = mkBase (x: x + 1); };
  c2b = compose { modules = mkBase (x: x + 2); };
in
{
  flake.tests.compose-parity = {
    # ---- the decision path is live -------------------------------------------------------------
    test-warm-fires-through-the-migrated-predicate = {
      expr = armWarm.trace.mode;
      expected = "warm";
    };
    # The splice actually reused locs; a "warm" mode over an empty reuse set would be a warm label on
    # a cold evaluation and the parity cells below would pass for the wrong reason.
    test-warm-reuses-the-untouched-locs = {
      expr = armWarm.trace.reused;
      expected = [
        "fleet.name"
        "fleet.size"
        "hooks"
      ];
    };
    test-base-carries-no-trace = {
      expr = ovBase ? trace;
      expected = false;
    };

    # ---- §3.1's two arms ------------------------------------------------------------------------
    test-cold-parity-values = {
      expr = (image armWarm).values;
      expected = (image armCold).values;
    };
    test-cold-parity-provenance = {
      expr = (image armWarm).provenance;
      expected = (image armCold).provenance;
    };

    # ---- the comparator's two hedges are LIVE on this subject ------------------------------------
    # Three legs, each independently falsifiable, and the last two are the positive/negative controls
    # that keep the first from being a zero out of a predicate that could not have matched: the cut
    # fired, functions were nulled, and a token that is not there reads absent.
    test-control-comparator-hedges-are-live = {
      expr = {
        cycleCutFired = countIn "<cycle:" (image armWarm).values > 0;
        functionsNulled = countIn "null" (image armWarm).values > 0;
        absentTokenReadsZero = countIn "qzwvxk" (image armWarm).values == 0;
      };
      expected = {
        cycleCutFired = true;
        functionsNulled = true;
        absentTokenReadsZero = true;
      };
    };

    # ---- the RED controls -----------------------------------------------------------------------
    test-control-ordinary-leaf-moves-values = {
      expr = (image ovDiffering).values != (image armWarm).values;
      expected = true;
    };
    test-control-added-def-moves-provenance = {
      expr = (image ovProvSeed).provenance != (image armWarm).provenance;
      expected = true;
    };

    # ---- the H1 blindness probe, with its seed integrity asserted first -------------------------
    test-control-h1-seed-is-a-function-on-both-sides = {
      expr =
        builtins.isFunction c2a.values.hooks.transform && builtins.isFunction c2b.values.hooks.transform;
      expected = true;
    };
    test-control-h1-seed-carries-two-different-functions = {
      expr = c2a.values.hooks.transform 1 != c2b.values.hooks.transform 1;
      expected = true;
    };
    test-control-h1-seed-holds-provenance-fixed = {
      expr = (image c2a).provenance;
      expected = (image c2b).provenance;
    };
    # The reading. GREEN — the two images are equal — is the PREDICTED outcome and the refusal.
    test-control-h1-blind-class-reads-green = {
      expr = (image c2a).values == (image c2b).values;
      expected = true;
    };
  };
}
