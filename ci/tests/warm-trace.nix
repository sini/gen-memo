# The admission test and the observed record — the two functions over data that decide whether a
# caller may ask an evaluator for a warm pass, and what a consumer gets to read about the answer.
#
# THE SUBJECT HERE IS A DECISION SOMEONE ELSE MADE. Every other warm suite in this repository hands
# an engine to a fold and checks what came back; nothing below touches an engine, because nothing in
# `warmTrace.nix` calls one. The fixtures are therefore literal records standing in for an
# evaluator's published decision, and that is not a stub of a fold — it is the actual argument type,
# since the observation's whole contract is "given this record and whether an edit was made, what
# crosses to the consumer".
{
  genMemo,
  ...
}:
let
  inherit (genMemo) warmAdmits warmTrace;

  # An evaluator's published decision, in the shape the migrating content observed: a mode, a reason
  # for it, the two loc partitions, and the module classification. The values are illustrative; the
  # SHAPE is the contract.
  decision = {
    mode = "warm";
    reason = null;
    reused = [
      "fleet.hosts"
      "fleet.environments"
    ];
    remerged = {
      scopeSettings = true;
    };
    modules = {
      clean = [ "<engine>" ];
      dirty = [ ];
      edited = [ ];
    };
  };

  # The same, for a warm pass the evaluator refused. A refusal is an answer, and `reason` is the
  # whole of what a caller learns about it.
  coldDecision = decision // {
    mode = "cold";
    reason = "edit carries more than the reuse-bearing argument";
    reused = [ ];
  };

  # A caller's projection, standing in for whatever result the observation is spliced onto. Two keys
  # is enough: the cells below are about what the splice ADDS, and a wider projection would only
  # make the assertion longer.
  projection = {
    values = 1;
    provenance = 2;
  };

  observe = edited: decision: projection // warmTrace { inherit edited decision; };

  # The edit shapes the admission test discriminates, as ONE list, so the two cells below read the
  # same subject through two instruments. Order matters and is asserted, not incidental.
  editFixtures = [
    { modules = [ ]; } # the reuse-bearing argument alone      ⇒ admissible
    { specialArgs = { }; } # a different argument entirely     ⇒ refused
    {
      modules = [ ];
      specialArgs = { };
    } # the reuse-bearing argument AND another                 ⇒ refused
    { } # no edit at all                                       ⇒ refused
    { tree = null; } # a replacement rather than an append      ⇒ refused
    {
      modules = [ ];
      engineArgs = { };
    } # the reuse-bearing argument AND another, again          ⇒ refused
  ];
in
{
  flake.tests.warm-trace = {
    # ── the admission test

    # THE ABSOLUTE READING. Stated as the classification of every fixture rather than as a pair of
    # spot checks: a predicate answering one constant passes any single arm, and the shape of this
    # list — one `true` among five `false` — is what says the test discriminates rather than
    # refuses everything. Position 3 is the case the whole rule exists for — the reuse-bearing
    # argument present AND a second one — held beside position 1, which it is easily confused with.
    test-admission-classifies-every-edit-shape = {
      expr = map (warmAdmits "modules") editFixtures;
      expected = [
        true
        false
        false
        false
        false
        false
      ];
    };

    # THE DIFFERENTIAL, against the test as its origin wrote it — the parameterised form instanced
    # at the origin's own key must decide identically, edit for edit. This is what reds if the
    # migrated predicate drifts into a weaker relation (`elem`, a subset test, a prefix match), each
    # of which passes position 1 and changes the answer somewhere in the tail.
    #
    # WHAT IT CANNOT SEE, so its green is not read as wider than it is: a misconception shared by
    # both sides. The reference below is a literal re-statement, not an independent derivation, so
    # this cell pins the migration and not the rule.
    test-admission-matches-the-form-it-migrated-from = {
      expr =
        map (warmAdmits "modules") editFixtures
        == map (e: builtins.attrNames e == [ "modules" ]) editFixtures;
      expected = true;
    };

    # THE KEY IS THE CALLER'S, AND THIS IS THE CELL THAT SAYS SO. Both arms in one run: the named
    # key admits, and the key the origin happened to use does NOT admit when it is not the one
    # named. A predicate that ignored its parameter and matched a built-in name would pass every
    # cell above and fail exactly here — which is the whole reason the parameter is not a default.
    test-admission-reads-the-key-it-is-given = {
      expr = [
        (warmAdmits "roots" { roots = [ ]; })
        (warmAdmits "roots" { modules = [ ]; })
      ];
      expected = [
        true
        false
      ];
    };

    # ── the observed record and its attachment rule

    # The asymmetry, both arms in one run. A result reached without an edit has no decision to
    # observe; a result reached through one carries it. Asserted on the SPLICED projection rather
    # than on the fragment, because the contract a consumer meets is about the result.
    test-attachment-follows-the-edit = {
      expr = [
        (observe false decision ? trace)
        (observe true decision ? trace)
      ];
      expected = [
        false
        true
      ];
    };

    # The splice adds the observation AND NOTHING ELSE, in either direction. Stated over names
    # rather than over presence: a fragment that returned the whole decision, or that carried a
    # sibling key of its own, satisfies the cell above and fails this one.
    test-splice-adds-only-the-observation = {
      expr = [
        (builtins.attrNames (observe false decision))
        (builtins.attrNames (observe true decision))
      ];
      expected = [
        [
          "provenance"
          "values"
        ]
        [
          "provenance"
          "trace"
          "values"
        ]
      ];
    };

    # The evaluator's answer crosses VERBATIM. Compared by value, not by shape, so a projection that
    # kept the names and rebuilt the contents would red.
    test-observation-carries-the-answer-verbatim = {
      expr = (observe true decision).trace;
      expected = {
        mode = "warm";
        reason = null;
        reused = [
          "fleet.hosts"
          "fleet.environments"
        ];
        remerged = {
          scopeSettings = true;
        };
        modules = {
          clean = [ "<engine>" ];
          dirty = [ ];
          edited = [ ];
        };
      };
    };

    # And it is NARROWED to the five published fields. The fixture carries a sixth that an evaluator
    # would have no reason to publish; it must not cross. This is the cell that reds if the
    # observation degenerates into passing the decision through, which every other cell here accepts.
    test-observation-narrows-to-the-published-five = {
      expr = builtins.attrNames (observe true (decision // { internalMemo = "not a consumer's"; })).trace;
      expected = [
        "mode"
        "modules"
        "reason"
        "remerged"
        "reused"
      ];
    };

    # A REFUSED WARM PASS IS AN OBSERVATION TOO. The attachment rule keys on the edit, not on the
    # answer — a caller that learned nothing when the warm pass was declined would have no channel
    # for the reason it was declined, which is the field it most needs.
    test-a-refused-pass-is-observed-with-its-reason = {
      expr = [
        (observe true coldDecision).trace.mode
        (observe true coldDecision).trace.reason
      ];
      expected = [
        "cold"
        "edit carries more than the reuse-bearing argument"
      ];
    };

    # THE OBSERVATION FORCES NOTHING, and the cell is built so that failing to hold that aborts
    # rather than reds. Three of the fixture's five fields throw on contact; the record is still
    # constructible, its names still readable, and a field that does not throw still reads. At the
    # evaluator this shape was migrated from, two of the five enumerate the whole declared-loc
    # partition when read, so an observation that forced them would charge every consumer of the
    # trace for a partition most of them never look at.
    #
    # The result deliberately carries only names and one scalar — nothing that throws is in the
    # compared value, so the comparison itself cannot be what forces them.
    test-observation-forces-nothing = {
      expr =
        let
          t =
            (observe true (
              decision
              // {
                reused = throw "forced: reused";
                remerged = throw "forced: remerged";
                modules = throw "forced: modules";
              }
            )).trace;
        in
        [
          (builtins.toString (builtins.length (builtins.attrNames t)))
          t.mode
        ];
      expected = [
        "5"
        "warm"
      ];
    };
  };
}
