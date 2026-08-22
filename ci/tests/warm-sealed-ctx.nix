# THE PLANE, RUN AGAINST THE CTX THE PRODUCTION ASSEMBLER ACTUALLY SEALS.
#
# Every other warm suite here assembles its `ctx` by hand. That is the right shape for them — they
# hold the cone and the decision still, which is what those cells are about — but it leaves one
# thing unmeasured, and it is the thing that went wrong: a hand-assembled fixture agrees with the
# library because the same author wrote both, so the suite can be green against a record shape that
# NOTHING produces. That is exactly how the gap this suite exists for stayed invisible.
#
# WHAT WENT WRONG, ON THE RECORD, because the shape of the fix is only defensible against it.
# `gen-scope`'s `foldEquations` is the sole production assembler of the ctx this plane consumes. It
# sealed the node map as `roots` and did not seal the scope RECORD at all — so the declared vertex
# order and the kind registry stopped at the entry, and the warm fold, which must hand a record to
# `evalWarm`, could not be written against the real seal no matter what it read. The hand fixtures
# could not see it: they supplied whatever the library asked for.
#
# ⇒ THIS SUITE TAKES ITS CTX FROM `foldEquations` AND NOWHERE ELSE. Nothing here constructs a ctx
# field. If the seal stops publishing something the plane reads, these cells fail at evaluation,
# which is the signal the hand fixtures structurally cannot give.
#
# The schedule is a fixture record rather than a scheduler's output, for the reason gen-scope's own
# fold suite states: the entry reads exactly one field off it and forces the value itself, so a
# fixture carrying that field exercises everything the entry does with a schedule. What validated
# the grammar is the scheduler's concern and is asserted where the scheduler lives.
{
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride;

  hostKinds = genScope.mkKinds [ (genScope.mkKind { name = "host"; }) ];

  # `consumer` reads `producer` across a declared edge, so the cone has somewhere to reach and the
  # parity claim below is not a claim about one isolated node.
  mkScope =
    v:
    genScope.buildRoots {
      kinds = hostKinds;
      decls = {
        producer.v = v;
        consumer = { };
      };
      types = {
        producer = "host";
        consumer = "host";
      };
    };

  equations = {
    imports = {
      name = "imports";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _self: _id: [ ];
    };
    p-val = {
      name = "p-val";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "resolution";
      compute = self: id: (self.node id).decls.v or 0;
    };
    sees = {
      name = "sees";
      kind = "synthesized";
      readsAttrs = [ "p-val" ];
      stratum = "resolution";
      compute = self: id: if id == "consumer" then (self.get "producer" "p-val") + 100 else 0;
    };
  };
  schedule = { inherit equations; };

  # The declared relation must over-declare the cross-node read for the cone to be sound — the same
  # contract `warm-override-cross-node.nix` states, here supplied to the real entry.
  declaredDependencies = id: if id == "consumer" then [ "producer" ] else [ ];

  sealed =
    v:
    genScope.foldEquations {
      scope = mkScope v;
      inherit schedule declaredDependencies;
      parseParent = _: null;
    };

  cold = sealed 1;
  warmed = warmOverride engine cold {
    id = "producer";
    newDecls = {
      v = 9;
    };
  };
  fresh = sealed 9;

  probe =
    ctx: id: attr:
    ctx.eval.get id attr;
in
{
  flake.tests.warm-sealed-ctx = {
    # ── THE CELL THIS SUITE EXISTS FOR ──
    # The plane accepts the sealed ctx and produces an evaluation from it. Stated separately from
    # the parity claim below because the two fail for different reasons: this one reds when the seal
    # and the plane's read set have drifted apart, which is a shape defect, not a value defect.
    test-the-plane-runs-on-the-sealed-ctx = {
      expr = probe warmed "producer" "p-val";
      expected = 9;
    };

    # Byte-parity (Reps–Teitelbaum–Demers 1983 soundness) through the REAL seal: the warm result
    # equals a cold fold of the same scope with the declaration pre-applied. The other suites make
    # this claim over a hand-built ctx; this is the one that makes it over the assembled one.
    test-sealed-warm-equals-sealed-cold = {
      expr =
        builtins.all (a: probe warmed "consumer" a == probe fresh "consumer" a) [
          "sees"
          "p-val"
        ]
        && probe warmed "producer" "p-val" == probe fresh "producer" "p-val";
      expected = true;
    };

    # THE ARM. `consumer` is not the edited node, so its value moves only if the cone was read
    # correctly off the sealed accessor. Without this the parity cell holds against a plane that
    # recomputed everything AND against one that reused everything, since both sides would agree.
    test-sealed-cone-consumer-is-armed = {
      expr = probe cold "consumer" "sees" != probe fresh "consumer" "sees";
      expected = true;
    };

    # The fold returns a ctx that is still one: the record it hands on carries the edited scope AND
    # the node map in step. A `roots` left at its pre-edit value is a stale map under a live name,
    # and nothing else here would observe it — the plane reads `scope`, so only this cell can.
    test-returned-ctx-keeps-roots-in-step-with-scope = {
      expr = warmed.roots == warmed.scope.nodes && warmed.roots.producer.decls.v == 9;
      expected = true;
    };

    # The seal's own fields survive the fold rather than being dropped by it: the plane returns
    # `ctx // {…}`, so a consumer holding the result still has what the assembler published.
    test-returned-ctx-still-carries-the-seal = {
      expr = builtins.all (f: warmed ? ${f}) [
        "accessor"
        "attributes"
        "declaredDependencies"
        "equations"
        "eval"
        "parseParent"
        "roots"
        "schedule"
        "scope"
        "settings"
        "trace"
      ];
      expected = true;
    };
  };
}
