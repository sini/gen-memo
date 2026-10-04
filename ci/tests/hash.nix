{ genPrelude, lib, ... }:
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
  lazyThrow = {
    a = throw "gen-memo test: lazy";
    b = 1;
  };
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
        root = (project drv).__drvPath == drv.drvPath;
        inAttrs = project { pkg = drv; };
        inList = project [ drv ];
        threeLevel = project {
          a = {
            b = [ { c = drv; } ];
          };
        };
      };
      expected = {
        root = true;
        inAttrs = {
          pkg = project drv;
        };
        inList = [ (project drv) ];
        threeLevel = {
          a = {
            b = [
              {
                c = project drv;
              }
            ];
          };
        };
      };
    };
    # The image of a derivation is its own attributes, keyed by the drvPath it reads and never by
    # the output path, which it blinds to `__outPath` as at every other position. The output attributes and `all` are what make a derivation
    # self-referential, and they are absent from it.
    test-project-drv-image-keys = {
      expr = {
        keyed = (project drv).__drvPath == drv.drvPath;
        keys = builtins.attrNames (project drv);
      };
      expected = {
        keyed = true;
        keys = [
          "__drvPath"
          "__outPath"
          "args"
          "builder"
          "drvAttrs"
          "name"
          "outputName"
          "system"
          "type"
        ];
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
            pkg = project drv;
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
    # (1) The projection is NOT injective, and the only reason is that it seals and drops: two
    # derivations differing in a function they carry share an image. It is NOT idempotent, though its
    # codomain is a subset of its domain: the key escape (den-hoag-x67vn) renames the image's own
    # `__drvPath` when the image is projected again, so a derivation's image written out literally no
    # longer compares equal to the derivation. Before the escape all three idempotence arms read true
    # and the literal image collided; that collision was a spelling, and it is closed by design.
    test-projection-is-not-injective = {
      expr = {
        nonInjectiveBySealing = project (drv // { f = _: 1; }) == project (drv // { f = _: 2; });
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
        literalImageCollides = project (project drv) == project drv && project drv != drv;
        literalTagSeparates = project { __drvPath = drv.drvPath; } != project drv;
      };
      expected = {
        nonInjectiveBySealing = true;
        idempotentAtRoot = false;
        idempotentThreeLevel = false;
        notTheIdentity = true;
        literalImageCollides = false;
        literalTagSeparates = true;
      };
    };

    # ── den-hoag-c5cj: THE COLLISIONS A DERIVATION'S IMAGE NOW SEPARATES. ──
    # Each pair is two values a cold evaluation distinguishes, and each read UNCHANGED under the
    # bare `{ __drvPath }` image: (1) a literal tag against the derivation; (2) the marker shape, a
    # derivation overlaid with `//`, which keeps its drvPath, at the root and inside a config value;
    # (3) the output-path coercion, under which `toJSON` reads an attrset carrying `outPath` as
    # that string alone. `same` is the control that the separation is not bought by collapsing
    # every pair.
    test-c5cj-image-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
        atDepth = d: {
          x.y = [ d ];
        };
      in
      {
        expr = {
          literalTag = sep { __drvPath = drv.drvPath; } drv;
          marker = sep (drv // { version = "1"; }) (drv // { version = "2"; });
          markerMetaAtDepth = sep (atDepth (drv // { meta.description = "a"; })) (
            atDepth (drv // { meta.description = "b"; })
          );
          outPathSibling =
            sep
              {
                outPath = "x";
                a = 1;
              }
              {
                outPath = "x";
                a = 2;
              };
          outPathString = sep "x" { outPath = "x"; };
          same = sep (atDepth (drv // { version = "1"; })) (atDepth (drv // { version = "1"; }));
        };
        expected = {
          literalTag = true;
          marker = true;
          markerMetaAtDepth = true;
          outPathSibling = true;
          outPathString = true;
          same = false;
        };
      };

    # THE OUTERMOST `outPath` IS BLINDED, NOT DROPPED. An overlay of it keeps the drvPath, and a
    # cold `"${drv}"` reads the overlaid path, so dropping it read the pair UNCHANGED outside the declared residue.
    # `same` is the control that the separation is not bought by collapsing every pair.
    test-c5cj-outermost-outpath-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          overlay = sep drv (drv // { outPath = "/nix/store/other"; });
          same = sep drv (drv // { outPath = drv.outPath; });
        };
        expected = {
          overlay = true;
          same = false;
        };
      };

    # A NESTED DERIVATION'S `drvPath` IS NEVER READ, which is the ruled reason for sealing it:
    # reading it instantiates whatever it reaches. R2 pins only that it does not enter the image;
    # this pins that it is not forced. Its `drvPath` throws, so a read would make the hash null.
    # `outermostReadIsNull` is the control that the poison fires where the image does read it.
    test-c5cj-nested-drvpath-is-never-read =
      let
        poisoned = {
          type = "derivation";
          drvPath = throw "nested drvPath read";
          outPath = throw "nested outPath read";
        };
      in
      {
        expr = {
          nestedUnreadHashes = builtins.isString (hashGuarded hashOf (drv // { sub = poisoned; }));
          outermostReadIsNull = hashGuarded hashOf { pkg = poisoned; } == null;
        };
        expected = {
          nestedUnreadHashes = true;
          outermostReadIsNull = true;
        };
      };

    # ── THE STATED RESIDUE, R1–R3 AND R5 (den-hoag-c5cj, the declared ADR-0025 item 1 exception). ──
    # Each pair is distinguished by a cold evaluation and read UNCHANGED by the plane, and each is
    # pinned as a collision so that closing one is a visible change rather than a silent one:
    # (R1) a changed function inside a derivation's attributes, sealed present/absent;
    # (R2) a nested derivation swapped where it does not feed the outer drvPath, sealed
    # present/absent and its drvPath never read; (R3) any change inside `passthru` or `tests`, or
    # in a top-level attribute named in `passthru` — a `tests` holding a literal `__sealed` record
    # included, because the seal forgets content whatever spells it; (R5) a derivation's output
    # attributes and `all`, which the image drops — overlaid or absent. All of these FORGET, and
    # none is closed by the key escape. `r4OutPath` is the struck member (den-hoag-x67vn): a literal
    # `__outPath` was a SPELLING of the blinded `outPath`, and the escape separates it by design.
    # The controls are the edges of each seal: presence separates, and a nested derivation that IS
    # a build input separates through the outer drvPath.
    test-c5cj-residue-is-stated =
      let
        same = a: b: hashEq (hashGuarded hashOf a) (hashGuarded hashOf b);
        e = mkDrv "gen-memo-residue-e";
        f = mkDrv "gen-memo-residue-f";
        withInput =
          dep:
          derivation {
            name = "gen-memo-residue-outer";
            system = "x86_64-linux";
            builder = "/bin/sh";
            args = [
              "-c"
              "true"
            ];
            inherit dep;
          };
        withPassthru = k: drv // { passthru.k = k; } // { inherit k; };
      in
      {
        expr = {
          r1Function = same (drv // { f = _: 1; }) (drv // { f = _: 2; });
          r2NestedSwap = same (drv // { sub = e; }) (drv // { sub = f; });
          r2NestedSwapAtDepth = same (drv // { x.y = [ e ]; }) (drv // { x.y = [ f ]; });
          r3Tests = same (drv // { tests.x = 1; }) (drv // { tests.x = 2; });
          r3Passthru = same (withPassthru 1) (withPassthru 2);
          r3TestsSealSpelled = same (drv // { tests.x = 1; }) (drv // { tests.__sealed = true; });
          r4OutPath = same { __outPath = "x"; } { outPath = "x"; };
          r5OutOverlay = same drv (drv // { out = e; });
          r5AllOverlay = same drv (drv // { all = [ e ]; });
          r5MarkerRecord = same (removeAttrs drv [
            "all"
            "out"
          ]) drv;
          controlFunctionPresence = same (drv // { f = _: 1; }) (drv // { f = 1; });
          controlNestedPresence = same (drv // { sub = e; }) (drv // { sub = "x"; });
          controlTestsPresence = same drv (drv // { tests = { }; });
          controlBuildInput = same (withInput e) (withInput f);
          controlOutermostSwap = same { pkg = e; } { pkg = f; };
        };
        expected = {
          r1Function = true;
          r2NestedSwap = true;
          r2NestedSwapAtDepth = true;
          r3Tests = true;
          r3Passthru = true;
          r3TestsSealSpelled = true;
          r4OutPath = false;
          r5OutOverlay = true;
          r5AllOverlay = true;
          r5MarkerRecord = true;
          controlFunctionPresence = false;
          controlNestedPresence = false;
          controlTestsPresence = false;
          controlBuildInput = false;
          controlOutermostSwap = false;
        };
      };

    # ── den-hoag-x67vn: THE KEY ESCAPE SEPARATES EVERY SPELLING, ONE CELL PER SPELLING. ──
    # Each `pair` is a value whose data literally spells a stand-in the image writes, against the
    # value that stand-in replaces. Each read UNCHANGED before the escape, and separates because no
    # user key's escaped name is a stand-in key. `same` is the control that the separation is not
    # bought by separating everything.
    test-x67vn-literal-sealed-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          pair = sep (drv // { f = _: 1; }) (drv // { f.__sealed = true; });
          same = sep (drv // { f = _: 1; }) (drv // { f = _: 1; });
        };
        expected = {
          pair = true;
          same = false;
        };
      };
    test-x67vn-literal-nested-drv-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
        e = mkDrv "gen-memo-residue-e";
      in
      {
        expr = {
          pair = sep (drv // { s = e; }) (drv // { s.__nestedDrv = true; });
          same = sep (drv // { s = e; }) (drv // { s = e; });
        };
        expected = {
          pair = true;
          same = false;
        };
      };
    test-x67vn-literal-blinded-tostring-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          pair = sep (drv // { m.____toString.__sealed = true; }) (drv // { m.__toString = _: "x"; });
          same = sep (drv // { m.__toString = _: "x"; }) (drv // { m.__toString = _: "x"; });
        };
        expected = {
          pair = true;
          same = false;
        };
      };
    test-x67vn-literal-outpath-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          pair = sep { __outPath = "x"; } { outPath = "x"; };
          atDepth = sep { a.b = [ { __outPath = "x"; } ]; } { a.b = [ { outPath = "x"; } ]; };
          same = sep { outPath = "x"; } { outPath = "x"; };
        };
        expected = {
          pair = true;
          atDepth = true;
          same = false;
        };
      };
    test-x67vn-outpath-shadow-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          outermost = sep drv (drv // { __outPath = "junk"; });
          plain = sep { outPath = "x"; } {
            outPath = "x";
            __outPath = "junk";
          };
          same = sep drv (drv // { });
        };
        expected = {
          outermost = true;
          plain = true;
          same = false;
        };
      };
    test-x67vn-literal-image-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          pair = sep (project drv) drv;
          same = sep (project drv) (project drv);
        };
        expected = {
          pair = true;
          same = false;
        };
      };
    test-x67vn-literal-drvpath-separates =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          pair = sep (drv // { __drvPath = "z"; }) drv;
          same = sep (drv // { __drvPath = "z"; }) (drv // { __drvPath = "z"; });
        };
        expected = {
          pair = true;
          same = false;
        };
      };
    # THE ESCAPE IS INJECTIVE: its three branches have disjoint images, so a key and its escaped
    # spelling never meet. An escape that merged two of them would pass every cell above and fail here.
    test-x67vn-escape-is-injective =
      let
        sep = a: b: !(hashEq (hashGuarded hashOf a) (hashGuarded hashOf b));
      in
      {
        expr = {
          outPathOnce = sep { __outPath = 1; } { ___outPath = 1; };
          outPathTwice = sep { outPath = "x"; } { ___outPath = "x"; };
          standInEscaped = sep (drv // { f.___sealed = true; }) (drv // { f.__sealed = true; });
          underscoreDepth = sep { _a = 1; } { __a = 1; };
        };
        expected = {
          outPathOnce = true;
          outPathTwice = true;
          standInEscaped = true;
          underscoreDepth = true;
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

    test-lazy-throw-is-always-dirty = {
      expr = {
        caught = builtins.tryEval (hashGuarded hashOf lazyThrow);
        cold = lazyThrow.b;
      };
      expected = {
        caught = {
          success = true;
          value = null;
        };
        cold = 1;
      };
    };
    # `exhausts` walks past functions, so it can reach a throw `unhashable` never reaches: the
    # function-first member is the case where only the second walk throws.
    test-classify-names-a-throwing-walk = {
      expr = {
        throwFirst = classify lazyThrow;
        fnFirst = classify {
          a = x: x;
          b = throw "gen-memo test: after a function";
        };
      };
      expected = {
        throwFirst = "throws";
        fnFirst = "function";
      };
    };
    test-caller-hashof-throw-stays-loud = {
      expr =
        (builtins.tryEval (hashGuarded (_: throw "gen-memo test: caller hashOf") { w = 1; })).success;
      expected = false;
    };
    # CONTROLS: an acyclic value under the bound hashes to exactly the digest it had before the
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
      expr = hashGuarded hashOf (chain 2000);
      expected = "fd2b4a3d391af318f39b860f1fc9c57473a751819aee34e300dcea58cdaa7745";
    };

    # THE DEPTH BOUND LEAVES THE CALLER HALF THE EVALUATOR'S BUDGET, and this is the certificate.
    # Under 4500 open caller frames, the deepest value D admits (containers down to depth D - 1)
    # is still hashed by the plane's own `hashOf`, and the value whose walk runs longest (the
    # self-loop, exhausted on D) still returns. The next depth is refused, so the pair is
    # two-sided. The measured ceiling is 4990 `underFrames` levels for the self-loop (4992 for the
    # deepest admitted chain) on upstream Nix, Determinate and Lix at the default `max-call-depth`;
    # past it the abort this bound exists to prevent comes back.
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
    # THE WALK'S CALL DEPTH IS A FUNCTION OF D ALONE, NEVER OF WIDTH OR SIZE. A loop whose width
    # doubles every level, a 180-wide loop and a two-cycle all exhaust under the certificate's
    # 4500 open caller frames, and a derivation whose drvPath is a function or a loop is null.
    test-walk-call-depth-independent-of-width = {
      expr = underFrames 4500 (_: {
        branching = classify branching;
        wide = classify (
          let
            x = builtins.listToAttrs (
              builtins.genList (j: {
                name = "k${toString j}";
                value = x;
              }) 180
            );
          in
          x
        );
        twoCycle = classify twoCycle;
      });
      expected = {
        branching = "exhausted";
        wide = "exhausted";
        twoCycle = "exhausted";
      };
    };
    # THE WALK CERTIFIES WHAT `hashOf` IS HANDED, drvPath content included (gate v1 C1).
    test-drvpath-content-is-walked = {
      expr = {
        fn = builtins.tryEval (
          hashGuarded hashOf {
            pkg = {
              type = "derivation";
              drvPath = x: x;
            };
          }
        );
        loop = builtins.tryEval (
          hashGuarded hashOf {
            pkg =
              let
                d = {
                  type = "derivation";
                  drvPath = d;
                };
              in
              d;
          }
        );
      };
      expected = {
        fn = {
          success = true;
          value = null;
        };
        loop = {
          success = true;
          value = null;
        };
      };
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
          present = genPrelude.hasInfix "ANCHOR: R10.1-RIDER-CLASSKEY-CEILING" src;
          absentControl = genPrelude.hasInfix absentToken src;
        };
        expected = {
          present = true;
          absentControl = false;
        };
      };
  };
}
