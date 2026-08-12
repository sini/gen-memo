{ lib, ... }:
let
  inherit (import ../../lib/hash.nix { })
    hashEq
    hashMoved
    hashGuarded
    project
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

    # (2) The GENERAL cyclic class is NOT rescued, and it CANNOT BE PINNED HERE. A plain
    # self-referential attrset aborts the projection the same way it aborts the walk, and
    # that abort is uncatchable — `tryEval` does not contain a stack overflow — so a cell
    # asserting it would end this suite rather than fail. What is assertable is that the
    # witness is a live, ordinary, reachable value and not a contrived one: reads through
    # it work to any finite depth. It is the projection that cannot decide it.
    test-cyclic-residue-witness-is-live = {
      expr =
        let
          a = {
            me = a;
            x = 1;
          };
        in
        a.me.me.me.x;
      expected = 1;
    };
  };
}
