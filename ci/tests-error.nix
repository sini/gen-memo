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
# ── THE SECOND SUBJECT IN THIS FILE: `runScc`'s THREE REFUSALS, READ AS MESSAGES ──────────────────
# `ci/tests/restabilize.nix` asserts the exhausted-bound and undeclared-bound pair as
# `(tryEval …).success == false`, which is a claim that SOMETHING threw and says nothing about WHAT.
# A combinator carrying any one refusal satisfies a bare boolean, and the blame set — the members
# that owe a declaration, the members still moving and by how much, or the member that lacks a
# lattice — is the whole content of these three throws. Reading it needs `expectedError`, and `expectedError` needs a cell whose
# `expr` may abort, which is what this file is for.
#
# ★ `msg` IS A POSIX ERE, NOT A LITERAL, and the messages are JSON blobs: every `{`, `}`, `[` and `]`
# below is escaped. Unescaped, the run does not fail — it ERRORS with
# `Invalid range in '{}' in regular expression`, which reads as a broken subject rather than a broken
# expectation.
{
  lib,
  genMemo,
  genScope,
  engine,
  fx,
  prelude,
  ...
}:
let
  runScc = genMemo.runScc engine.ascend;

  # ── THE DOOR-CHECK BYTES (den-hoag-7gp66 P1, then P2) ──
  # `ci/tests/door-checks.nix` pins that each step's violations are CATCHABLE; a boolean cannot see
  # WHICH refusal fired, so WHICH — and that it names the door (R6) — is pinned here, anchored at
  # both ends, per row of `ci/doors.nix`. `[.]`, `[(]` and `[)]` neutralise the metacharacters, as
  # in gen-prelude's own goldens. A RECORD step has no unknown-field golden: an extra field is R5's
  # admitted case, and there is no message for a call that answers — except a guarded record's
  # sibling option, which is refused by name (`optionsStep`, G10).
  doors = import ./doors.nix {
    inherit
      lib
      genMemo
      engine
      fx
      ;
  };
  # gen-prelude's refusal text, composed with this library's own literal door, field and accepted
  # set (den-hoag-7jltk): every assertion kept, none of gen-prelude's wording copied.
  inherit (prelude) refusals;
  exactly = text: "^" + prelude.escapeRegex text + "$";
  name = d: "gen-memo.${d}";
  optionGoldens = key: row: {
    "test-${lib.toLower key}-unknown-option-message" = {
      expr = row.door { unknownField = 1; };
      expectedError = {
        type = "ThrownError";
        msg = exactly (refusals.unknownOption (name key) row.optional "unknownField");
      };
    };
  };
  recordGoldens =
    key: row:
    let
      k = lib.toLower key;
    in
    {
      "test-${k}-missing-required-field-message" = {
        expr = row.step (builtins.removeAttrs row.good [ row.drop ]);
        expectedError = {
          type = "ThrownError";
          msg = exactly (refusals.missingField (name key) row.required row.drop);
        };
      };
      "test-${k}-non-attrset-argument-message" = {
        expr = row.step 1;
        expectedError = {
          type = "ThrownError";
          msg = exactly (refusals.recordNotASet (name key) row.required 1);
        };
      };
    }
    // lib.optionalAttrs (row ? guardedBy) (
      let
        o = builtins.head doors.options.${row.guardedBy}.optional;
      in
      {
        "test-${k}-misplaced-option-message" = {
          expr = row.step (row.good // { ${o} = null; });
          expectedError = {
            type = "ThrownError";
            msg = exactly (refusals.guardedField (name key) (name row.guardedBy) o);
          };
        };
      }
    );

  # Fixture 3 of `ci/tests/restabilize.nix`, reproduced here because that file's `let` exports
  # nothing: a 1-member self-loop whose recompute strictly increments under an overwrite join, so it
  # never quiesces, capped at `maxIter = 5`.
  divergeAccessor = fx.mkPlaneAccessor {
    edges = [
      {
        from = "x";
        to = "x";
      }
    ];
    nodeData = {
      x = { };
    };
  };
  divergeRun = runScc {
    accessor = divergeAccessor;
    store = { };
    higherStrata = { };
    recompute =
      _a: s: _m:
      s.x + 1;
    scc = [ "x" ];
    lattices = {
      x = {
        bottom = 0;
        join = _: v: v;
        maxIter = 5;
      };
    };
  };

  # Fixture 2b's shape: fixture 2's peer-agree SCC with member `a`'s `maxIter` removed. The ascent
  # itself is untouched, so the refusal is caused by the missing declaration and by nothing else.
  agreeAccessor = fx.mkPlaneAccessor {
    edges = [
      {
        from = "a";
        to = "b";
      }
      {
        from = "b";
        to = "a";
      }
    ];
    nodeData = {
      a = {
        self = 5;
      };
      b = {
        self = 3;
      };
    };
  };
  overwriteLattice = {
    bottom = 0;
    join = _prev: v: v;
    maxIter = 100;
  };
  agreeRecompute2b =
    a: s: m:
    let
      dep = builtins.head (a.dependencies m);
    in
    if (a.nodeData m).self > s.${dep} then (a.nodeData m).self else s.${dep};
  undeclaredRun = runScc {
    accessor = agreeAccessor;
    store = { };
    higherStrata = { };
    recompute = agreeRecompute2b;
    scc = [
      "a"
      "b"
    ];
    lattices = {
      a = removeAttrs overwriteLattice [ "maxIter" ];
      b = overwriteLattice;
    };
  };

  # ── AN EXTRA LATTICE KEY IS ADMITTED AND NEVER READ (den-hoag-m6y9p / den-hoag-k2p6 OQ-1):
  # quiescence is structural `==` for every member, so an `eq` on member `a`'s lattice is an
  # extra key of the record. `eq = _: _: false` never declares quiescence, so a driver that read
  # it would not settle where the clean run does. Same accessor and SCC as `cleanRun` below.
  eqKeyedRun = runScc {
    accessor = agreeAccessor;
    store = { };
    higherStrata = { };
    recompute = agreeRecompute2b;
    scc = [
      "a"
      "b"
    ];
    lattices = {
      a = overwriteLattice // {
        eq = _: _: false;
      };
      b = overwriteLattice;
    };
  };
  # ── THE THIRD REFUSAL (den-hoag-8iw8): a DIRECT caller that supplies no lattice for member `b`.
  # `build`'s own precheck never reaches `runScc` with an undeclared member, but `runScc` is public,
  # and without its own guard the first `lattices.${m}` read aborts with `attribute 'b' missing`,
  # which `tryEval` cannot contain. Same accessor and SCC as above, `a`'s lattice complete.
  undeclaredLatticeRun = runScc {
    accessor = agreeAccessor;
    store = { };
    higherStrata = { };
    recompute = agreeRecompute2b;
    scc = [
      "a"
      "b"
    ];
    lattices = {
      a = overwriteLattice;
    };
  };
  # The identical accessor/SCC/recompute, neither member's lattice carrying an extra key.
  cleanRun = runScc {
    accessor = agreeAccessor;
    store = { };
    higherStrata = { };
    recompute = agreeRecompute2b;
    scc = [
      "a"
      "b"
    ];
    lattices = {
      a = overwriteLattice;
      b = overwriteLattice;
    };
  };

in
{
  config = {
    flake.testsError.door-checks =
      lib.concatMapAttrs optionGoldens doors.options // lib.concatMapAttrs recordGoldens doors.records;

    # ── `runScc`'s THREE REFUSALS, AT BLAME-SET GRANULARITY ──
    # Anchored at both ends, so a message that merely CONTAINS the expected text does not pass, and
    # written out in full rather than summarised: the blame set is the content, and a cell asserting
    # only the prefix would go green on a refusal that named the wrong members.
    flake.testsError.runScc-refusals = {
      # The bound is exhausted at 5 rounds and the member is still moving 5 -> 6. `iters`, `scc` and
      # `lastDelta` are all read: a driver that lost the round counter, or a blame built over the
      # wrong component, reds here where a boolean would not.
      test-the-exhausted-bound-blames-the-still-moving-member = {
        expr = builtins.deepSeq divergeRun true;
        expectedError = {
          type = "ThrownError";
          msg = ''^gen-memo: fixpoint did not converge: \{"iters":5,"lastDelta":\{"x":\{"next":6,"prev":5\}\},"scc":\["x"\],"why":"fixpoint-diverged"\}$'';
        };
      };
      # `nodes` is the member that owes a declaration and `scc` is the whole component, and the two
      # are DIFFERENT lists here on purpose: a refusal that blamed the component rather than the
      # undeclared member would satisfy any predicate that read only one of them.
      test-an-undeclared-bound-blames-the-member-that-owes-one = {
        expr = builtins.deepSeq undeclaredRun true;
        expectedError = {
          type = "ThrownError";
          msg = ''^gen-memo: cyclic member declares no maxIter: \{"nodes":\["a"\],"scc":\["a","b"\],"why":"undeclared-maxiter"\}$'';
        };
      };
      # THE MISSING-LATTICE REFUSAL (den-hoag-8iw8). `type` is the load-bearing half: before the
      # guard this read was an uncatchable `TypeError` (`attribute 'b' missing`), and a named
      # `ThrownError` is what makes it catchable. `nodes` (the member lacking a lattice) and `scc`
      # (the component) differ on purpose, as above.
      test-a-missing-lattice-blames-the-member-that-lacks-one = {
        expr = builtins.deepSeq undeclaredLatticeRun true;
        expectedError = {
          type = "ThrownError";
          msg = ''^gen-memo: cyclic member declares no lattice: \{"nodes":\["b"\],"scc":\["a","b"\],"why":"undeclared-lattice"\}$'';
        };
      };
    };

    # An extra lattice key is admitted and not read, the lattice record's existing disposition for
    # any key it does not name (whether that record should be closed is den-hoag-c54n4 OQ2): the
    # run whose member `a` carries `eq = _: _: false` settles exactly where the clean run does. A
    # SUCCESS cell, so that a driver which read `eq`, or refused the key, is a visible change. The
    # two clean cells are its control and every refusal cell's above: `runScc` does not refuse
    # every lattice.
    flake.tests.runScc-extra-lattice-key = {
      test-an-eq-key-is-admitted-and-not-read = {
        expr = {
          inherit (eqKeyedRun) a b;
        };
        expected = {
          inherit (cleanRun) a b;
        };
      };
      test-clean-lattice-settles-under-structural-eq-a = {
        expr = cleanRun.a;
        expected = 5;
      };
      test-clean-lattice-settles-under-structural-eq-b = {
        expr = cleanRun.b;
        expected = 5;
      };
    };
  };
}
