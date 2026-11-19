# A NODE THE SUBSTRATE GROWS, UNDER THE REAL PLANE — `warmOverride` (`warmDecision`, then gen-scope's
# `evalWarm`) against a fresh `foldEquations` of the edited data, for every shape of a grown child.
#
# A grown child's record is a function of its host's evaluation: an `nta` child's seed is a sub-value
# of a host attribute, and a spawned child's builder reads through its host's handle. The relation the
# evaluator publishes therefore has every grown child depend on its host, and the decision built over
# it must put the child in the cone of a host edit. ADR-0008 item 2 is the contract: a warm read equals
# the cold read of the edited data.
#
# The shapes (one fixture; `variant` chooses which in-unit reads are declared):
#   C1 `nta` child, depth 1        C2 depth 2           D3 depth 3          C3 on-demand `nta` child
#   C4 spawn copying its host      SS spawn of a spawn  C5 spawn reading `x` through its host's edge
#   DD `z` reads `r2`'s grown child                     HR host reads its own child through `getNta`
#   C6 child reads its host        XZ one grown member reads an external node `xz`
#   AE host `r2b` reads `zb`, which reads `r2b`'s grown child
# Controls: NU (an unrelated host and its child stay clean), NC (a registered child is not dirtied by
# its parent's edit), W9 (`warm-read-seam`'s driver-store cell, unchanged).
#
# AE IS THE RECORDED PRICE. Its attribute instances are acyclic, but no node-level relation is both
# sound and acyclic: an edit to `zb` must reach `r2b`, and an edit to `r2b` moves the child `zb`
# reads. The relation carries the cycle, the warm plane serves AE fresh, and the acyclic consumers
# (`build` here) refuse it by name, catchably, rather than serve a stale value. The message is pinned
# in `ci/tests-error.nix`.
{
  graph,
  genMemo,
  genScope,
  engine,
  prelude,
  ...
}:
let
  fx = import ../grown-child.nix {
    inherit
      graph
      genMemo
      genScope
      engine
      prelude
      ;
  };
  inherit (fx)
    nta
    ntaK
    hChild
    zChild
    hrChild
    aeChild
    xk
    acyclicVariant
    cold
    moves
    dirtyFor
    builds
    fresh
    parity
    grows
    ;
in
{
  flake.tests.warm-grown-child = {
    test-W1-an-nta-child-moves-with-its-host = {
      expr = parity (
        moves acyclicVariant { r.defs = [ { s = 2; } ]; } [
          [
            (nta "r" "x")
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W2-both-levels-of-a-depth-2-nta-move = {
      expr = parity (
        moves acyclicVariant { n.defs = [ { s.s = 2; } ]; } [
          [
            (nta "n" "x")
            "defs"
          ]
          [
            (nta (nta "n" "x") "x")
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W10-every-level-of-a-depth-3-nta-moves = {
      expr = parity (
        moves acyclicVariant { d3.defs = [ { s.s.s = 2; } ]; } [
          [
            (nta "d3" "x")
            "defs"
          ]
          [
            (nta (nta "d3" "x") "x")
            "defs"
          ]
          [
            (nta (nta (nta "d3" "x") "x") "x")
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W3-an-on-demand-nta-child-moves-with-its-host = {
      expr = parity (
        moves acyclicVariant { o.defs = [ { s = 2; } ]; } [
          [
            (nta "o" "y")
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W4-a-spawned-child-moves-with-its-host = {
      expr = parity (
        moves acyclicVariant { q.defs = [ 2 ]; } [
          [
            "q-c"
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W11-a-spawn-of-a-spawn-moves-at-both-levels = {
      expr = parity (
        moves acyclicVariant { ss.defs = [ 2 ]; } [
          [
            "ss-c"
            "defs"
          ]
          [
            "ss-c-c"
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W5-a-spawned-child-moves-with-a-node-its-host-declares = {
      expr = parity (
        moves acyclicVariant { x.defs = [ 2 ]; } [
          [
            "w-c"
            "defs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W12-a-reader-of-a-grown-child-moves-with-the-host = {
      expr = parity (
        moves acyclicVariant { r2.defs = [ { s = 2; } ]; } [
          [
            zChild
            "defs"
          ]
          [
            "z"
            "zRead"
          ]
        ]
      );
      expected = fresh;
    };
    test-W13-a-host-reading-its-own-child-moves = {
      expr = parity (
        moves acyclicVariant { hr.defs = [ { s = 2; } ]; } [
          [
            hrChild
            "defs"
          ]
          [
            "hr"
            "hostAgg"
          ]
        ]
      );
      expected = fresh;
    };
    test-C6-a-child-reading-its-host-moves = {
      expr = parity (
        moves acyclicVariant { h.defs = [ { s = 2; } ]; } [
          [
            hChild
            "defs"
          ]
          [
            hChild
            "hostDefs"
          ]
        ]
      );
      expected = fresh;
    };
    test-W15-a-grown-member-moves-with-the-external-node-it-reads = {
      expr = parity (
        moves acyclicVariant { xz.defs = [ 9 ]; } [
          [
            xk
            "zDep"
          ]
        ]
      );
      expected = fresh;
    };
    # Host reads child, child reads host, and both: each relation is acyclic and `build` accepts it.
    test-W14-build-accepts-every-in-unit-read = {
      expr = {
        hr = builds [ "hr" ];
        c6 = builds [ "c6" ];
        both = builds acyclicVariant;
      };
      expected = {
        hr = true;
        c6 = true;
        both = true;
      };
    };
    # Host reads child (HR), and host and child reading each other (HR+C6): each relation builds AND a
    # host edit propagates warm = fresh. Positive controls for the shapes the growth unit keeps acyclic.
    test-HR-builds-and-updates = {
      expr = {
        built = builds [ "hr" ];
        update = parity (
          moves [ "hr" ] { hr.defs = [ { s = 2; } ]; } [
            [
              hrChild
              "defs"
            ]
            [
              "hr"
              "hostAgg"
            ]
          ]
        );
      };
      expected = {
        built = true;
        update = fresh;
      };
    };
    test-HR-and-C6-build-and-update = {
      expr = {
        built = builds acyclicVariant;
        update = parity (
          moves acyclicVariant { hr.defs = [ { s = 2; } ]; } [
            [
              hrChild
              "defs"
            ]
            [
              "hr"
              "hostAgg"
            ]
          ]
        );
        updateC6 = parity (
          moves acyclicVariant { h.defs = [ { s = 2; } ]; } [
            [
              hChild
              "defs"
            ]
            [
              hChild
              "hostDefs"
            ]
          ]
        );
      };
      expected = {
        built = true;
        update = fresh;
        updateC6 = fresh;
      };
    };
    # An edit that grows a member (EN: a new `nta` child; ES: a new spawned child): the new member was
    # in no prior, so nothing of it is served from one, and the caller's node set and the new member's
    # value equal a fresh fold.
    test-EN-a-grown-nta-member-is-not-served-from-the-prior = {
      expr = grows {
        hf.defs = [
          {
            a = 1;
            b = 2;
            c = 3;
          }
        ];
      } (ntaK "hf" "x" "c") "defs";
      expected = {
        equal = true;
        grew = true;
      };
    };
    test-ES-a-grown-spawned-member-is-not-served-from-the-prior = {
      expr = grows {
        sk.kids = [
          "a"
          "b"
        ];
      } "sk-b" "v";
      expected = {
        equal = true;
        grew = true;
      };
    };
    # The negative controls: what an edit dirties, and nothing more.
    test-W6-a-host-edit-dirties-its-unit-and-no-other = {
      expr = dirtyFor "r";
      expected = [
        (nta "r" "x")
        "r"
      ];
    };
    test-W7-a-parent-edit-does-not-dirty-a-registered-child = {
      expr = dirtyFor "p";
      expected = [ "p" ];
    };
    test-W15-an-external-edit-dirties-only-the-member-reading-it = {
      expr = dirtyFor "xz";
      expected = [
        xk
        "xz"
      ];
    };
    test-W8-affected-from-an-edit-root = {
      expr = {
        r = genMemo.affected cold "r";
        q = genMemo.affected cold "q";
        x = genMemo.affected cold "x";
      };
      expected = {
        r = [ (nta "r" "x") ];
        q = [ "q-c" ];
        x = [
          "w"
          "w-c"
        ];
      };
    };
    # AE: the warm plane serves it fresh, and `build` refuses the cyclic relation catchably.
    test-AE-the-warm-plane-serves-a-cross-unit-cycle-fresh = {
      expr = parity (
        moves [ "ae" ] { r2b.defs = [ { s = 2; } ]; } [
          [
            aeChild
            "defs"
          ]
          [
            "zb"
            "zRead"
          ]
          [
            "r2b"
            "aRead"
          ]
        ]
      );
      expected = fresh;
    };
    test-AE-build-refuses-a-cross-unit-cycle-catchably = {
      expr = builds [ "ae" ];
      expected = false;
    };
  };
}
