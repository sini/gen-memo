# THE DOORS (den-hoag-7gp66 P1, then P2 — `prelude.door`) — every published step taking a record
# catches its own violations.
#
# A native closed formal (`{ hashOf }:`) aborts UNCATCHABLY on an unknown or a missing argument —
# not even `builtins.tryEval` sees it, which is ADR-0025 item 1's named defect. Every record step in
# `../doors.nix` is a `prelude.door`, so the same violations are NAMED and CATCHABLE. Each cell `seq`s
# the STEP applied to its argument and nothing else (no later argument, no field read), so a refusal
# is observed where the step is applied. Covered, per row:
#   - an OPTIONS step admits `{ }`, and refuses an unknown option (G1/G4)
#   - a RECORD step admits its good record, refuses a missing field (D2) and a non-attrset, and
#     admits a field no step names (G2, R5's stated price; G10-ctl on the guarded rows)
#   - a record behind an options step refuses each of that step's own names (`optionsStep`, G10)
#   - every step publishes its row as its contract, read as data and through the functor-aware
#     reader (D3)
#   - a non-default option reaches the partially applied door and changes the answer (G3)
#
# `success == false` pins catchability, not the message; WHICH refusal fired, and that it names the
# door (R6), is pinned byte-for-byte in `ci/tests-error.nix`'s `door-checks` group.
{
  lib,
  genMemo,
  prelude,
  engine,
  fx,
  ...
}:
let
  F = import ../doors.nix {
    inherit
      lib
      genMemo
      engine
      fx
      ;
  };

  applied = step: r: (builtins.tryEval (builtins.seq (step r) true)).success;
  unknown = {
    unknownField = 1;
  };
  each = f: builtins.mapAttrs (_: f);
  flag = v: names: lib.genAttrs names (_: v);
  guarded = lib.filterAttrs (_: r: r ? guardedBy) F.records;

  # Every options door on the published surface, read off its `__contract` rather than a hand list,
  # so a new one is seen whether or not a row was written for it.
  isDoor = v: builtins.isAttrs v && v ? __contract && v ? __functor;
  surfaceOptionDoors = builtins.filter (
    n: isDoor genMemo.${n} && !genMemo.${n}.__contract.open && genMemo.${n}.__contract.required == [ ]
  ) (builtins.attrNames genMemo);

  # G3's subjects: the chain a -> b -> c with `b` marked as a cut point.
  cut = {
    cutoffs.b = true;
  };
  lattices0 = {
    fixpoint.lattices = { };
  };
in
{
  flake.tests.door-checks = {
    # ★ LIVE CONTROLS FOR THE WHOLE SUITE: `tryEval` catches an ordinary throw, and a non-throwing
    # value answers. Without these, a broken `applied` reading one constant satisfies half the cells.
    test-control-tryeval-catches-an-ordinary-throw = {
      expr = applied (_: throw "control probe, not this suite's subject") null;
      expected = false;
    };
    test-control-tryeval-answers-a-non-throwing-value = {
      expr = applied (x: x) 1;
      expected = true;
    };
    # The table is the subject; a row dropped from it would drop its cells silently.
    test-door-table-rows = {
      expr = {
        options = builtins.attrNames F.options;
        records = builtins.attrNames F.records;
      };
      expected = {
        options = [
          "build"
          "identitiesHeld"
          "why"
          "whyFor"
          "whyNot"
          "whyNotFor"
        ];
        records = [
          "build"
          "identitiesHeld"
          "mkAccessor"
          "needsEval"
          "runScc"
        ];
      };
    };

    test-the-empty-options-are-admitted-at-every-options-step = {
      expr = each (d: applied d.door { }) F.options;
      expected = each (_: true) F.options;
    };
    # G1/G4: refused when the options are applied, before any operand or record.
    test-an-unknown-option-is-refused-catchably-at-every-options-step = {
      expr = each (d: applied d.door unknown) F.options;
      expected = each (_: false) F.options;
    };
    test-a-non-attrset-options-argument-is-refused-catchably = {
      expr = each (d: applied d.door 1) F.options;
      expected = each (_: false) F.options;
    };
    # D3: the contract is published as data, and the functor-aware reader reads the same map.
    test-every-options-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.door.__contract) optional required open;
        functionArgs = prelude.functionArgs d.door;
      }) F.options;
      expected = each (d: {
        inherit (d) optional;
        required = [ ];
        open = false;
        functionArgs = flag true d.optional;
      }) F.options;
    };

    test-the-good-record-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step d.good) F.records;
      expected = each (_: true) F.records;
    };
    # D2
    test-a-missing-field-is-refused-catchably = {
      expr = each (d: applied d.step (builtins.removeAttrs d.good [ d.drop ])) F.records;
      expected = each (_: false) F.records;
    };
    test-a-non-attrset-record-is-refused-catchably = {
      expr = each (d: applied d.step 1) F.records;
      expected = each (_: false) F.records;
    };
    # G2 / R5, and G10-ctl on the guarded rows: a field no step names is admitted.
    test-an-extra-field-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step (d.good // unknown)) F.records;
      expected = each (_: true) F.records;
    };
    # G10: each of the options step's own names (from that step's `__contract`), given on the record
    # instead, is refused. The answer is the names ADMITTED.
    test-every-option-is-refused-at-every-guarded-record-step = {
      expr = each (
        d:
        builtins.filter (o: applied d.step (d.good // { ${o} = null; })) (
          F.options.${d.guardedBy}.door.__contract.optional
        )
      ) guarded;
      expected = each (_: [ ]) guarded;
    };
    # Every options door on the surface is classified: a chained one has a guarded record row, and
    # the rest are named as not chained. `surfaceOptionDoors` is pinned as the enumerator's live
    # control: a walk that found nothing would leave `unclassified` empty too.
    test-every-options-door-on-the-surface-is-classified = {
      expr = {
        unclassified = builtins.filter (n: !(guarded ? ${n}) && !(builtins.elem n F.notChained)) (
          surfaceOptionDoors ++ [ "identitiesHeld" ]
        );
        inherit surfaceOptionDoors;
      };
      expected = {
        unclassified = [ ];
        surfaceOptionDoors = [
          "build"
          "why"
          "whyFor"
          "whyNot"
          "whyNotFor"
        ];
      };
    };
    test-every-record-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.step.__contract) required open;
        functionArgs = prelude.functionArgs d.step;
      }) F.records;
      expected = each (d: {
        inherit (d) required;
        open = true;
        functionArgs = flag false d.required;
      }) F.records;
    };

    # G3: a non-default option reaches the partially applied door (agrees with the full call) and
    # changes the answer (differs from `{ }`). `identitiesHeld`'s one option shows only in its
    # refusal, so its G3 is the byte golden in `warm-identity.nix`, and G4 stands for it here.
    test-a-non-default-option-reaches-the-partial-application = {
      expr =
        let
          good = F.records.build.good;
          b0 = genMemo.build { } engine;
          b1 = genMemo.build lattices0 engine;
          w =
            d: o: id:
            d o F.ctx "c" id;
        in
        {
          build = {
            agrees = (b1 good) ? fixpoint == (genMemo.build lattices0 engine good) ? fixpoint;
            differs = (b1 good) ? fixpoint != (b0 good) ? fixpoint;
          };
          why = {
            agrees = (w genMemo.why cut "a").verdict == (genMemo.why cut F.ctx "c" "a").verdict;
            differs = (w genMemo.why cut "a").verdict != (w genMemo.why { } "a").verdict;
          };
          whyFor = {
            agrees = (w genMemo.whyFor cut "a").verdict == (genMemo.whyFor cut F.ctx "c" "a").verdict;
            differs = (w genMemo.whyFor cut "a").verdict != (w genMemo.whyFor { } "a").verdict;
          };
          whyNot = {
            agrees = (w genMemo.whyNot cut "a").reason == (genMemo.whyNot cut F.ctx "c" "a").reason;
            differs = (w genMemo.whyNot cut "a").reason != (w genMemo.whyNot { } "a").reason;
          };
          whyNotFor = {
            agrees = (w genMemo.whyNotFor cut "a").reason == (genMemo.whyNotFor cut F.ctx "c" "a").reason;
            differs = (w genMemo.whyNotFor cut "a").reason != (w genMemo.whyNotFor { } "a").reason;
          };
        };
      expected =
        lib.genAttrs
          [
            "build"
            "why"
            "whyFor"
            "whyNot"
            "whyNotFor"
          ]
          (_: {
            agrees = true;
            differs = true;
          });
    };
  };
}
