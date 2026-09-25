{ lib, ... }:
let
  inherit (import ../../lib/hash.nix { })
    hashEq
    hashMoved
    hashGuarded
    project
    classify
    maxDepth
    ;

  # A literal system, never `builtins.currentSystem`: nothing here is built, and
  # `currentSystem` is absent under the pure evaluation the runner uses.
  mkDrv =
    name:
    derivation {
      inherit name;
      system = "x86_64-linux";
      builder = "/bin/sh";
      args = [
        "-c"
        "true"
      ];
    };
  drv = mkDrv "gen-memo-projection-fixture";
  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  # Non-well-founded values: a self-loop, a branching loop, a two-cycle and an unboundedly
  # generated value. Each is an ordinary, readable Nix value; none has a finite walk.
  selfLoop =
    let
      x = {
        s = x;
        v = 1;
      };
    in
    x;
  branching =
    let
      x = {
        a = x;
        b = x;
      };
    in
    x;
  twoCycle =
    let
      a = {
        s = b;
      };
      b = {
        s = a;
      };
    in
    a;
  generated =
    let
      f = n: {
        s = f (n + 1);
        inherit n;
      };
    in
    f 0;
  # A well-founded chain nesting `n` attrsets inside the root: its containers sit at depths 0..n.
  chain = n: builtins.foldl' (acc: _: { s = acc; }) { } (builtins.genList (x: x) n);
  # `k` evaluator call frames open around `f`. Nix does not eliminate tail calls, so each level
  # holds one frame (measured: the same caller-frame ceiling as a pending `0 +` at every level).
  underFrames = k: f: if k == 0 then f null else underFrames (k - 1) f;
in
{
  flake.tests."hash" = {
    test-hashEq-equal = {
      expr = hashEq "x" "x";
      expected = true;
    };
    test-hashEq-differ = {
      expr = hashEq "x" "y";
      expected = false;
    };
    test-hashEq-null-left = {
      expr = hashEq null "x";
      expected = false;
    };
    test-hashEq-null-right = {
      expr = hashEq "x" null;
      expected = false;
    };
    test-hashEq-null-both = {
      expr = hashEq null null;
      expected = false;
    }; # null==null is true in Nix; guard forces false
    test-hashMoved-null-both = {
      expr = hashMoved null null;
      expected = true;
    };
    test-hashMoved-equal = {
      expr = hashMoved "x" "x";
      expected = false;
    };

    # ── THE ADMISSION PROJECTION. ──
    # Every position, not the root: each of these four shapes ended the whole evaluation
    # with `error: stack overflow; max-call-depth exceeded` before the projection existed,
    # and none of them could be pinned by a cell, because an uncatchable abort takes the
    # suite with it. They are cells now, which is itself the observation.
    test-project-drv-at-every-position = {
      expr = {
        root = project drv;
        inAttrs = project { pkg = drv; };
        inList = project [ drv ];
        threeLevel = project {
          a = {
            b = [ { c = drv; } ];
          };
        };
      };
      expected = {
        root = {
          __drvPath = drv.drvPath;
        };
        inAttrs = {
          pkg = {
            __drvPath = drv.drvPath;
          };
        };
        inList = [ { __drvPath = drv.drvPath; } ];
        threeLevel = {
          a = {
            b = [
              {
                c = {
                  __drvPath = drv.drvPath;
                };
              }
            ];
          };
        };
      };
    };

    # The guard's own arms over the same shapes: a derivation now HASHES (it used to abort),
    # and a function beside one is still discriminated to null. Both directions in one cell,
    # so a guard that answered null to everything and one that answered a hash to everything
    # both fail.
    test-guard-hashes-drv-and-still-sees-functions = {
      expr = {
        nested =
          hashGuarded hashOf { pkg = drv; } == hashOf {
            pkg = {
              __drvPath = drv.drvPath;
            };
          };
        functionBesideDrv = hashGuarded hashOf {
          pkg = drv;
          f = x: x;
        };
        plainFunction = hashGuarded hashOf { f = x: x; };
        plainValue = hashGuarded hashOf { a = 1; } == hashOf { a = 1; };
      };
      expected = {
        nested = true;
        functionBesideDrv = null;
        plainFunction = null;
        plainValue = true;
      };
    };

    # THE MARKER WITHOUT THE ATTRIBUTE, which is why `isDrv` tests `? drvPath`. A predicate
    # matching the marker alone would read `drvPath` off this value and die there, and the
    # death is uncatchable — the failure mode the projection exists to remove, reappearing
    # at a different shape. It must fall through to ordinary descent.
    test-project-marker-without-drvpath-falls-through = {
      expr = project {
        type = "derivation";
        n = 1;
      };
      expected = {
        type = "derivation";
        n = 1;
      };
    };

    # THE TAG SEPARATES THE FALSE-CLEAN PAIR — a derivation and a plain string equal to its
    # drvPath. Under a bare-string projection these were identical and the plane would have
    # read a swap between them as unchanged, which is the unsound direction. Two distinct
    # derivations still differ, so the separation is not bought by collapsing everything.
    test-projection-does-not-collide-with-a-plain-string = {
      expr = {
        pairSeparated = project { pkg = drv; } != project { pkg = drv.drvPath; };
        distinctDrvsDiffer =
          project (mkDrv "gen-memo-projection-a") != project (mkDrv "gen-memo-projection-b");
        sameDrvAgrees = project (mkDrv "gen-memo-projection-a") == project (mkDrv "gen-memo-projection-a");
      };
      expected = {
        pairSeparated = true;
        distinctDrvsDiffer = true;
        sameDrvAgrees = true;
      };
    };

    # ── THE RESIDUE, STATED AS CELLS RATHER THAN AS PROSE. ──
    # (1) The projection is IDEMPOTENT and NOT the identity, so some value and its image are
    # distinct with the same image: an attrset written literally with the reserved key still
    # compares equal to a projected derivation. No tag closes that — the codomain is a subset
    # of the domain — so injectivity is narrowed here, never achieved.
    test-projection-is-not-injective = {
      expr = {
        idempotentAtRoot = project (project drv) == project drv;
        idempotentThreeLevel =
          project (project {
            a = {
              b = [ { c = drv; } ];
            };
          }) == project {
            a = {
              b = [ { c = drv; } ];
            };
          };
        notTheIdentity = project drv != drv;
        literalTagStillCollides = project { __drvPath = drv.drvPath; } == project drv;
      };
      expected = {
        idempotentAtRoot = true;
        idempotentThreeLevel = true;
        notTheIdentity = true;
        literalTagStillCollides = true;
      };
    };

    # (2) THE GENERAL NON-WELL-FOUNDED CLASS FALLS BACK TO ALWAYS-DIRTY (den-hoag-5ahw). Each of
    # these ended the whole evaluation with `stack overflow; max-call-depth exceeded` before the
    # walk was bounded, and `tryEval` did not contain it. They are now `null`, which the plane reads
    # as always-dirty: a change of cost, never of answer.
    test-self-loop-is-always-dirty = {
      expr = {
        hash = hashGuarded hashOf selfLoop;
        caught = builtins.tryEval (hashGuarded hashOf selfLoop);
        reason = classify selfLoop;
      };
      expected = {
        hash = null;
        caught = {
          success = true;
          value = null;
        };
        reason = "exhausted";
      };
    };
    test-branching-loop-is-always-dirty = {
      expr = hashGuarded hashOf branching;
      expected = null;
    };
    test-two-cycle-is-always-dirty = {
      expr = hashGuarded hashOf twoCycle;
      expected = null;
    };
    test-generated-value-is-always-dirty = {
      expr = hashGuarded hashOf generated;
      expected = null;
    };
    # A deep WELL-FOUNDED value past the depth bound loses reuse and nothing else. At depth 5000
    # the cell asserts only that the guard RETURNS — a hash or null — because which of the two is
    # a property of D, not of this cell; at 50000, past every evaluator's ceiling, it is null.
    test-deep-acyclic-returns = {
      expr = {
        d5000 =
          let
            r = builtins.tryEval (hashGuarded hashOf (chain 5000));
          in
          r.success && (r.value == null || builtins.isString r.value);
        d50000 = hashGuarded hashOf (chain 50000);
      };
      expected = {
        d5000 = true;
        d50000 = null;
      };
    };
    # The value is live, and only its walk is bounded: reads through it work to any finite depth.
    test-cyclic-residue-witness-is-live = {
      expr = selfLoop.s.s.s.v;
      expected = 1;
    };

    # CONTROLS: an acyclic value under both bounds hashes to exactly the digest it had before the
    # walk was bounded (the literals were read at gen-memo 3336b88 and are unchanged at 80dc2f0).
    test-control-acyclic-hash-unchanged = {
      expr = hashGuarded hashOf {
        a = 1;
        b = [
          2
          3
          { c = "x"; }
        ];
      };
      expected = "490a8b50fc8d89b1894ebbbfc75566c0d9aa4f3e4a8fcdbf84a6c54f83e321f7";
    };
    test-control-deep-acyclic-hash-unchanged = {
      expr = hashGuarded hashOf (chain 3000);
      expected = "b13977a3b7d5f7995a3a46756b4a8b1929150541b82ac6f154557c2ce5e47c11";
    };

    # THE DEPTH BOUND LEAVES THE CALLER HALF THE EVALUATOR'S BUDGET, and this is the certificate.
    # Under 4500 open caller frames, the deepest value D admits (containers down to depth D - 1)
    # is still hashed by the plane's own `hashOf`, and the value whose walk runs longest (the
    # self-loop, exhausted on D) still returns. The next depth is refused, so the pair is
    # two-sided. The measured ceiling is 4990 caller frames on upstream Nix, Determinate and Lix at
    # the default `max-call-depth`; past it the abort this bound exists to prevent comes back.
    test-depth-bound-leaves-caller-margin = {
      expr = underFrames 4500 (_: {
        deepestAdmitted = builtins.isString (hashGuarded hashOf (chain (maxDepth - 1)));
        firstRefused = hashGuarded hashOf (chain maxDepth);
        selfLoop = hashGuarded hashOf selfLoop;
      });
      expected = {
        deepestAdmitted = true;
        firstRefused = null;
        selfLoop = null;
      };
    };
    # THE WALK'S OWN CALL DEPTH DOES NOT GROW WITH B. A value that exhausts on B, a loop whose width
    # doubles every level, is classified under 9000 open caller frames.
    test-walk-call-depth-independent-of-size-bound = {
      expr = underFrames 9000 (_: classify branching);
      expected = "exhausted";
    };

    # ── R§10.1, RIDER 3 — THE RETIREMENT RECORD SURVIVES ──
    # `lib/hash.nix` carries, immediately above `hashGuarded`, the record of what gen-resolve's
    # retired `classKey` construct's stated ceiling — a conservative key needing a byte-identity
    # gate as its total correctness oracle — means for this binding, which decides reuse on a
    # digest with no such gate behind it — R§10.1 (a retirement names what it carries forward or
    # it is a deletion). This cell pins that the record SURVIVES, never that it is true; the
    # record itself states the ceiling is unmet here and neither installs the gate nor repairs
    # the collision class `den-hoag-c5cj` already measures (`den-hoag-p3y9`).
    #
    # ★ THE LIVE CONTROL IS THE SECOND ARM OF THIS SAME EXPR, not a second cell — a one-armed
    # `present = true` would still pass against a `match` that has stopped discriminating.
    # `absentControl` is a probe DERIVED from the file's own content (its sha256), not a literal
    # typed here: a hardcoded random string, once committed, is itself a published token that a
    # later sweep can quote back as a false live control (measured, `den-hoag-n3or2`). A content
    # hash is reproducible, changes automatically if the file changes, and cannot occur as a
    # literal substring of the text it was hashed from.
    test-r10-1-rider-classkey-ceiling-record-survives =
      let
        src = builtins.readFile ../../lib/hash.nix;
        absentToken = builtins.hashString "sha256" src;
      in
      {
        expr = {
          present = builtins.match ".*ANCHOR: R10\\.1-RIDER-CLASSKEY-CEILING.*" src != null;
          absentControl = builtins.match ".*${absentToken}.*" src != null;
        };
        expected = {
          present = true;
          absentControl = false;
        };
      };
  };
}
