# THE TWO ACCESSOR CONTRACTS, MEASURED AT THE SEAM BETWEEN THEM.
#
# `lib/graph-view.nix` carries the statement of record: the plane is parametric over its dependency
# oracle, and the two instantiations that ship differ in the relation's DOMAIN. The caller-built
# relation is TOTAL over probed ids — the discovery feature depends on probing an id before it is a
# member — while a substrate-contracted relation is FAIL-CLOSED, refusing a non-member by name.
# The modes are disjoint by construction, so nothing here is a guard; these cells pin the two
# behaviours the documentation asserts, and the ONE place the two published provenance queries stop
# agreeing.
#
# ★★★ WHY DOCUMENTATION NEEDS CELLS AT ALL. The ruled disposition is a domain statement with no code
# behind it, and a domain statement fails in exactly one way: silently, when a later edit makes one
# of its clauses untrue and no one is told. Two clauses here are edit-sensitive and neither is
# visible in any other suite — that the discovery walk REALLY probes a non-member (a membership
# check quietly added upstream of it would make the whole statement moot while every existing cell
# stayed green), and that the boundary is LOUD rather than absorbed into a default.
#
# ★★ WHAT THESE CELLS DO NOT CLAIM, said plainly so their green is not read as wider than it is.
# The fail-closed relation below is this suite's MODEL of the contracted mode, not gen-scope's
# relation: it reproduces the CONTRACT — a non-member is refused by name — and nothing about the
# substrate's actual wording, which is pinned in the substrate's own suite where the message is
# constructed. What is measured here is what this plane does when handed such a relation: whether it
# probes, whether the refusal survives to the caller, and what each provenance query answers.
{
  lib,
  genMemo,
  engine,
  ...
}:
let
  build = genMemo.build engine;
  applyEdgeDelta = genMemo.applyEdgeDelta engine;
  inherit (genMemo) why whyFor;

  # ---- THE FIXTURE ----------------------------------------------------------------------------
  #
  # A chain a -> b -> c whose three ids ARE nodes, plus `z -> w`, two ids the relation KNOWS about
  # and that are NOT nodes. That combination is the whole point: it is the shape
  # `ci/tests/structural.nix` already relies on for the new-producer sub-build, and it is precisely
  # the shape a contracted relation refuses to have.
  weights = {
    a = 1;
    b = 10;
    c = 100;
    z = 50;
    w = 7;
  };
  liveNodes = [
    "a"
    "b"
    "c"
  ];
  edgesOf =
    id:
    if id == "a" then
      [ "b" ]
    else if id == "b" then
      [ "c" ]
    else if id == "z" then
      [ "w" ]
    else
      [ ];

  # ★★★ THE REFUSAL, BUILT AS gen-graph BUILDS ITS OWN: ONE construction, TWO surfaces. The findings
  # function RETURNS the message and the relation THROWS the head of it, so the message this suite
  # asserts and the message the abort carries cannot come to state different things. An assertion
  # belongs on a returned message rather than on a caught throw — `builtins.tryEval` reports THAT
  # something refused and never WHY, so a cell resting on it alone would pass any refusal at all,
  # including one for an unrelated reason.
  membershipFindings =
    id:
    if builtins.elem id liveNodes then
      [ ]
    else
      [ "accessor.dependencies: '${id}' is not a node of the evaluated graph" ];

  # MODE 2 — substrate-contracted: fail-closed off the node set.
  contractedDeps =
    id:
    let
      findings = membershipFindings id;
    in
    if findings == [ ] then edgesOf id else throw (builtins.head findings);

  # MODE 1 — caller-built: total over probed ids. `nodes` is the LIVE set, and the relation answers
  # for ids outside it, which is what the discovery walk consumes.
  callerBuiltDeps = edgesOf;

  # ★★★ THE PROBE WITNESS. A caller-built relation identical to the one above except that the
  # non-member `z` maps to a marker id. The marker can enter a result through exactly one route —
  # someone calling `dependencies "z"` — so finding it downstream is POSITIVE evidence that the
  # discovery walk probed a non-member, rather than an inference from the fact that it aborted
  # under the other relation.
  witnessDeps = id: if id == "z" then [ "probe-witness" ] else edgesOf id;

  mkAcc = deps: {
    nodes = liveNodes;
    dependencies = deps;
    nodeData = id: { weight = weights.${id} or 0; };
    parent = _id: null;
  };

  recompute =
    a: s: id:
    (a.nodeData id).weight + lib.foldl' (sum: dep: sum + s.${dep}) 0 (a.dependencies id);
  hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);

  ctxOf =
    deps:
    build {
      accessor = mkAcc deps;
      inherit recompute hashOf;
    };
  callerCtx = ctxOf callerBuiltDeps;
  contractedCtx = ctxOf contractedDeps;
  witnessCtx = ctxOf witnessDeps;

  # THE CROSS-MODE OPERATION: repoint `a` at `z`, an id that is not a member. Under mode 1 this is
  # the discovery feature working as specified; under mode 2 it is the boundary being crossed.
  discover = ctx: applyEdgeDelta ctx "a" [ "z" ];
  completes = x: (builtins.tryEval (builtins.deepSeq x true)).success;
in
{
  flake.tests."accessor-modes" = {
    # ===== THE REFUSAL, AS A READABLE VALUE ===================================================

    # The contract's message for a non-member, asserted on the RETURNED finding. This is the half a
    # caught throw cannot give, and it is what makes the abort cells below attributable.
    test-contracted-mode-refuses-a-non-member-by-name = {
      expr = membershipFindings "z";
      expected = [ "accessor.dependencies: 'z' is not a node of the evaluated graph" ];
    };

    # ★ The refusal DISCRIMINATES. Without this, the cell above passes a contract that refuses
    # every id, which would make every abort below trivially true and mean nothing.
    test-control-contracted-mode-admits-a-member = {
      expr = membershipFindings "b";
      expected = [ ];
    };

    # And the relation itself answers for a member, so the fixture is a working relation rather
    # than one that throws on contact.
    test-control-contracted-relation-answers-for-a-member = {
      expr = contractedDeps "a";
      expected = [ "b" ];
    };

    # ===== MODE 1 · THE DISCOVERY FEATURE, AND THE PROBE IT RESTS ON ==========================

    # ★★★ THE DISCOVERY WALK REALLY PROBES A NON-MEMBER. `probe-witness` is reachable only through
    # `dependencies "z"`, and `z` is not in `nodes` — so its presence in the built store is direct
    # evidence of the probe. This is the clause the whole domain statement rests on: if a later edit
    # made the walk consult membership first, this cell reds and the statement gets re-read, instead
    # of quietly becoming a description of code that no longer behaves that way.
    test-discovery-probes-an-id-outside-the-node-set = {
      expr = builtins.elem "probe-witness" (builtins.attrNames (discover witnessCtx).store);
      expected = true;
    };

    # The feature itself, under the mode it belongs to: the non-member producer subgraph is found
    # and SUB-BUILT. w = 7, z = 50 + 7 = 57, a = 1 + 57 = 58.
    test-caller-built-mode-discovers-and-builds-new-producers = {
      expr = (discover callerCtx).store;
      expected = {
        a = 58;
        b = 110;
        c = 100;
        w = 7;
        z = 57;
      };
    };

    # ===== THE BOUNDARY, AT CONTACT ==========================================================

    # ★★★ THE CROSS-MODE PROBE ABORTS — the boundary is LOUD, not absorbed. Nothing on the discovery
    # path catches the refusal and substitutes a default, which is the failure direction that would
    # turn the ruled documentation into prose: a silently-empty discovery would leave a node
    # unbuilt and surface much later as a missing store key.
    test-cross-mode-discovery-refuses = {
      expr = completes (discover contractedCtx);
      expected = false;
    };

    # ★★★ THE DISCRIMINATION HALF, SAME FIXTURE, SAME RUN. The identical operation under the
    # caller-built relation COMPLETES. The two cells together say the refusal is the relation's
    # domain talking and not something wrong with the delta, the fixture, or the plane.
    test-control-same-delta-completes-in-caller-built-mode = {
      expr = completes (discover callerCtx);
      expected = true;
    };

    # ★ AND AN IN-SET DELTA IS CLEAN UNDER THE CONTRACTED RELATION, so the abort above is the
    # FOREIGN id and nothing else. Without this the cell above passes a contracted mode in which no
    # topology edit works at all — a much broader claim than the one being made.
    test-control-contracted-mode-accepts-an-in-set-delta = {
      expr = completes (applyEdgeDelta contractedCtx "a" [ "c" ]);
      expected = true;
    };

    # ===== THE PROVENANCE PAIR · THE ONE SILENT CELL, PINNED ==================================
    #
    # `why` and `whyFor` share `_verdict`, so their verdict BRANCHES cannot drift. They differ in
    # their MEMBERSHIP ORACLE — a walk versus a set lookup — and that is a different axis. Under the
    # contracted mode a foreign id splits them. Both halves are pinned here as the DOCUMENTED
    # behaviour (`lib/graph-view.nix`, and the scope note at `lib/provenance.nix`), not as a defect:
    # closing the gap means deciding membership a second time inside the plane, which is the
    # consumer-side guard the ruling declined.

    # `why` WALKS the relation, so it meets the refusal and aborts.
    test-why-aborts-on-a-foreign-id-in-contracted-mode = {
      expr = completes (
        why contractedCtx {
          id = "ghost";
          changedId = "c";
        }
      );
      expected = false;
    };

    # ★★★ `whyFor` LOOKS UP a cone bound once, so the same id misses and it answers — a plausible
    # verdict about a node that does not exist. THIS IS THE SILENT CELL, and writing it down is the
    # disposition: a reader who expects the pair to agree everywhere finds the exception here rather
    # than in production.
    test-whyFor-answers-unaffected-for-a-foreign-id-in-contracted-mode = {
      expr = whyFor contractedCtx { changedId = "c"; } "ghost";
      expected = {
        verdict = "unaffected";
      };
    };

    # ★ THE CONTROL THAT MAKES THE CELL ABOVE MEAN SOMETHING. `whyFor` does not answer `unaffected`
    # for everything: a real node that reaches the change comes back `recomputed`, over the same ctx
    # in the same run. Without this, a `whyFor` broken to a constant would pass.
    test-control-whyFor-still-decides-a-real-node = {
      expr = whyFor contractedCtx { changedId = "c"; } "a";
      expected = {
        verdict = "recomputed";
      };
    };

    # ★ AND `why` IS NOT SIMPLY BROKEN UNDER THIS ACCESSOR — it answers for a real node in the same
    # run it aborts for a foreign one. Without this, the abort cell passes a `why` that aborts on
    # everything, which would misattribute the cause to the walk rather than to the domain.
    test-control-why-still-decides-a-real-node = {
      expr =
        (why contractedCtx {
          id = "a";
          changedId = "c";
        }).verdict;
      expected = "recomputed";
    };

    # ★★ THE MODE DISCRIMINATION FOR THE PAIR: the SAME query, the SAME foreign id, under the
    # caller-built relation ANSWERS instead of aborting. This is what makes the divergence a
    # property of the CONTRACT rather than of `why`, and it is the cell that would red if someone
    # narrowed the caller-built domain to match the contracted one.
    test-control-why-answers-a-foreign-id-in-caller-built-mode = {
      expr =
        (why callerCtx {
          id = "ghost";
          changedId = "c";
        }).verdict;
      expected = "unaffected";
    };
  };
}
