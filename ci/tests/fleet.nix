# THE FLEET ARM — the plane's named enforcer, migrated from the measurement lab's Arm R.
#
# The lab modelled a real host fleet as a graph over this content and re-asserted its soundness
# oracle on the real corpus: nodes are a shared class-composition producer plus the fleet hosts,
# each host depends on the shared composition, and a localized single-host edit must recompute
# that host alone while every untouched host is served byte-identically from the prior store. The
# win is reuse ACROSS CHANGE — the skipped hosts' evaluations — and it is sound exactly when the
# incremental store equals a full rebuild's.
#
# ★★ WHAT MIGRATED AND WHAT DID NOT, stated up front because the two halves have different
# evidential weight and reading them as one would claim a coverage this file has not got.
#
#   MIGRATED IN FULL — the SOUNDNESS ORACLE. The byte gate (incremental store == full rebuild),
#   the poisoned-recompute proof that untouched hosts are never evaluated, the poison's own
#   liveness control, and the cone/untouched partition. These are properties of the plane over a
#   graph shape, they need no corpus, and they are what makes the saving a saving rather than a
#   wrong answer computed quickly.
#
#   MIGRATED AS ARITHMETIC — the FLOOR. The lab's floor is
#   `savedFraction.nrFunctionCalls >= 0.60` over evaluator counters. The DECISION half is the
#   plane's and is recomputed here: which hosts a single-host edit skips is exactly what the cone
#   decides, and that is what the floor is guarding — the lab's own note is that a saving falling
#   below 0.60 means the dedup cone grew unexpectedly. The COUNTER half is the lab's measurement,
#   transcribed below with its provenance; it is not re-measured here and is not claimed to be.
#
#   DID NOT MIGRATE — the LIVE RE-MEASUREMENT. The lab re-runs the fleet under evaluator counters
#   over the real configuration corpus. Evaluator counters are not readable from inside a pure
#   evaluation, and the corpus is not in this repository; that arm stays where the corpus is. So
#   this suite cannot detect a change in what a host COSTS. It detects a change in which hosts are
#   SKIPPED, which is the plane's half of the same number.
#
#   AND THE RECOMPUTE IS SYNTHETIC. The lab's `recompute host` forces a host's real composition;
#   here it folds the node's data with the shared value. The graph shape, the edit, the cone and
#   the partition are the lab's; the work each node stands for is not.
{
  genMemo,
  graph,
  lib,
  ...
}:
let
  inherit (genMemo)
    build
    propagateEager
    dirtySet
    ;

  hosts = [
    "bitstream"
    "blade"
    "cortex"
  ];
  editHost = "bitstream";
  nodeIds = [ "shared" ] ++ hosts;

  # PER-HOST AND FLEET COMPOSITION COUNTERS, transcribed from the measurement lab's recorded
  # baseline (`ci/bench/baselines/g6-split.json`, `.hosts[*].baseline-composition.counters` and
  # `.fleet.baseline-composition.counters`, at lab revision 3e449ac). These are that lab's
  # measurement of the real corpus and are quoted, not re-derived — the whole point of the floor
  # is to weigh the plane's cone decision against what the skipped work actually cost.
  hostComposition = {
    bitstream = 17634072;
    blade = 17673112;
    cortex = 17677224;
  };
  fleetComposition = 52984408;

  # The lab's own recorded outcome for this edit, quoted so the migration can be checked against
  # it rather than merely re-run.
  recordedSkippedHosts = [
    "blade"
    "cortex"
  ];
  recordedSavedRecompute = 35350336;
  recordedSavedFraction = 0.6671837496042232;
  floor = 0.60;

  fleetAcc = graph.mkGraph {
    edges = map (h: {
      from = h;
      to = "shared";
    }) hosts;
    nodeData = lib.genAttrs nodeIds (id: {
      rev = "base";
    });
  };

  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  # Synthetic stand-in for the real per-host composition: the shared node hashes its own data, a
  # host folds its data with the shared value, so the shared node is a genuine dependency and a
  # shared-node edit would move every host (the pessimal case the lab records beside this one).
  recompute =
    acc: s: id:
    if id == "shared" then
      hashOf (acc.nodeData id)
    else
      hashOf {
        host = id;
        data = acc.nodeData id;
        shared = s.shared;
      };

  edit = {
    ${editHost} = {
      rev = "edited";
    };
  };

  ctx = build {
    accessor = fleetAcc;
    inherit recompute hashOf;
  };

  incremental = propagateEager ctx edit;

  editedAcc = fleetAcc // {
    nodeData = id: if id == editHost then edit.${editHost} else fleetAcc.nodeData id;
  };
  fullRebuild = build {
    accessor = editedAcc;
    inherit recompute hashOf;
  };

  cone = dirtySet ctx [ editHost ];
  untouched = builtins.filter (id: !(builtins.elem id cone)) nodeIds;

  # The poison proves the untouched nodes are never evaluated: a recompute that THROWS on them.
  # The incremental path must never call it there, so it succeeds; a full rebuild recomputes
  # everything and must therefore fail. The ASYMMETRY is the proof — either half alone proves
  # nothing, since a poison that never fires and a poison that is never reached look identical.
  poison =
    acc: s: id:
    if builtins.elem id untouched then throw "POISON: ${id} was recomputed" else recompute acc s id;
  poisonedCtx = ctx // {
    recompute = poison;
  };
  poisonedIncremental = propagateEager poisonedCtx edit;
  poisonedFullRebuild = build {
    accessor = fleetAcc;
    recompute = poison;
    inherit hashOf;
  };

  # THE FLOOR, recomputed. The skipped set comes from the plane's cone; the weights come from the
  # lab. Nix integer division truncates, so both operands are floated first — an integer division
  # here would report 0 and pass no floor at all.
  skippedHosts = builtins.filter (h: !(builtins.elem h cone)) hosts;
  savedRecompute = builtins.foldl' (sum: h: sum + hostComposition.${h}) 0 skippedHosts;
  savedFraction = (savedRecompute + 0.0) / (fleetComposition + 0.0);
in
{
  flake.tests.fleet = {
    # ── The soundness oracle. ──
    test-fleet-result-equals-full-rebuild = {
      expr = incremental.store == fullRebuild.store;
      expected = true;
    };

    test-fleet-untouched-reused = {
      expr = builtins.all (id: incremental.store.${id} == ctx.store.${id}) untouched;
      expected = true;
    };

    # deepSeq forces the store's VALUES, not just its spine — a poison throw inside an unforced
    # thunk would otherwise go unnoticed and this cell would pass by not looking.
    test-fleet-cone-only-recompute = {
      expr = (builtins.tryEval (builtins.deepSeq poisonedIncremental.store true)).success;
      expected = true;
    };

    test-fleet-poison-is-real = {
      expr = (builtins.tryEval (builtins.deepSeq poisonedFullRebuild.store true)).success;
      expected = false;
    };

    # ── The partition, against the lab's recorded one. ──
    test-fleet-cone-is-the-edited-host-alone = {
      expr = builtins.sort builtins.lessThan cone;
      expected = [ editHost ];
    };

    test-fleet-skipped-hosts-match-the-record = {
      expr = builtins.sort builtins.lessThan skippedHosts;
      expected = recordedSkippedHosts;
    };

    # ── The floor. ──
    test-fleet-arm-r-floor = {
      expr = savedFraction >= floor;
      expected = true;
    };

    # The floor is only meaningful if the arithmetic under it reproduces the lab's. Both halves:
    # the summed saving exactly, and the fraction to within the tolerance the lab's own
    # consistency check uses.
    test-fleet-saving-reproduces-the-record = {
      expr = {
        saved = savedRecompute == recordedSavedRecompute;
        fraction = (
          let
            d = savedFraction - recordedSavedFraction;
          in
          (if d < 0.0 then -d else d) < 1.0e-9
        );
      };
      expected = {
        saved = true;
        fraction = true;
      };
    };

    # THE FLOOR CELL CAN FAIL. A `>=` against a constant computed from constants would pass
    # whatever the plane did; what makes it a gate is that the numerator is a function of the
    # cone. Armed here: the same arithmetic over a cone that grew to include every host — the
    # regression the floor exists to catch — must fall below the floor.
    test-fleet-floor-would-catch-a-grown-cone = {
      expr =
        let
          grownCone = nodeIds;
          skipped = builtins.filter (h: !(builtins.elem h grownCone)) hosts;
          saved = builtins.foldl' (sum: h: sum + hostComposition.${h}) 0 skipped;
        in
        (saved + 0.0) / (fleetComposition + 0.0) >= floor;
      expected = false;
    };
  };
}
