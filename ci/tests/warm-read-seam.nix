# THE WARM PASS UNDER THE CODOMAIN CONTRACT, over the ctx the production assembler seals.
#
# The cold fold refuses a body's read across an edge its node did not declare. The warm pass is the
# same evaluator handed a prior and a decision, so it must refuse the same read: a warm answer the
# cold fold refuses is a byte-parity failure (ADR-0008 item 2), and an undeclared read the cold fold
# admitted would leave its reader outside the cone and serve it stale. Both seams are seeded —
# `self.node` (the record) and `self.get` (the attribute) — and the edit is put on each end of the
# edge: on the reader, which the warm pass must recompute, and on the producer, which the undeclared
# reader would otherwise be served stale from. The warm accessor's `nodeData` reads what the cold
# accessor reads, a spawned node included.
#
# The guard is the reader's three rebound names (`self.node`, `self.get`, `self.getRepresentative`).
# A read through another field of the reader that takes a target is not refused, cold or warm, and
# no cell here claims it is.
#
# Every refusal cell is a `tryEval` fact; the messages are the validators' (gen-scope's cells).
# Live controls: the declared arms answer, and answer what a fresh cold fold of the edited scope
# answers, so a plane refusing everything cannot pass.
{
  graph,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride build;
  refuses = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
  contractedFor =
    scope: rel:
    graph.mkDeclaredEdges (
      builtins.mapAttrs (_: ids: map (graph.mkNodeRef (id: scope.nodes ? ${id})) ids) rel
    );
  structural = {
    children = {
      name = "children";
      kind = "nta";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _: _: { };
    };
    imports = {
      name = "imports";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _: _: [ ];
    };
  };
  resolution = name: compute: {
    inherit name compute;
    kind = "synthesized";
    readsAttrs = [ ];
    stratum = "resolution";
  };
  hostKinds = genScope.mkKinds [ (genScope.mkKind { } "host") ];
  scopeAt =
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
  edge.consumer = [ "producer" ];
  sealed =
    equations: v: rel:
    let
      scope = scopeAt v;
    in
    genScope.foldEquations { } {
      inherit scope;
      schedule = { inherit equations; };
      declaredDependencies = contractedFor scope rel;
      parseParent = _: null;
    };
  # the cold read a real caller makes first, so the prior holds a value to reuse
  primed = ctx: builtins.seq (builtins.tryEval (ctx.eval.get "consumer" "sees")) ctx;
  sees = ctx: ctx.eval.get "consumer" "sees";

  # `self.node`: the reader acquires the producer's record
  byNode = sealed (
    structural
    // {
      sees = resolution "sees" (
        self: id: if id == "consumer" then (self.node "producer").decls.v + 100 else 0
      );
    }
  );
  # `self.get`: the reader demands the producer's attribute
  byGet = sealed (
    structural
    // {
      p-val = resolution "p-val" (self: id: (self.node id).decls.v or 0);
      sees = resolution "sees" (
        self: id: if id == "consumer" then self.get "producer" "p-val" + 100 else 0
      );
    }
  );

  # a spawned node: `millstone` (kind quern) spawns `winnow`
  spawnKinds = genScope.mkKinds [
    (genScope.mkKind { } "chaff")
    (genScope.mkKind {
      below = [ "chaff" ];
      spawns.chaff = _self: id: {
        winnow = {
          id = "winnow";
          parent = id;
          decls.v = 7;
        };
      };
    } "quern")
  ];
  spawnScope = genScope.buildRoots {
    kinds = spawnKinds;
    decls.millstone.x = 0;
    types.millstone = "quern";
  };
  spawnCold = genScope.foldEquations { } {
    scope = spawnScope;
    schedule.equations = structural;
    declaredDependencies = contractedFor spawnScope { };
    parseParent = id: if id == "winnow" then "millstone" else null;
  };
  spawnWarm = warmOverride engine spawnCold "millstone" { x = 1; };
  storeOf =
    acc:
    (build { } engine {
      accessor = acc;
      recompute =
        acc': _store: id:
        acc'.nodeData id;
      hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);
    }).store;
in
{
  flake.tests.warm-read-seam = {
    # ── g8qsy: the warm pass is armed with the relation the seal carries ──
    test-warm-undeclared-node-read-is-refused-reader-edited = {
      expr = refuses (sees (warmOverride engine (byNode 1 { }) "consumer" { w = 1; }));
      expected = true;
    };
    test-control-warm-declared-node-read-answers = {
      expr = sees (warmOverride engine (byNode 1 edge) "consumer" { w = 1; });
      expected = 101;
    };

    # ── 3deus: an undeclared `self.get` is refused warm, never served stale ──
    test-warm-undeclared-get-is-refused-not-stale-primed = {
      expr = refuses (sees (warmOverride engine (primed (byGet 1 { })) "producer" { v = 9; }));
      expected = true;
    };
    # the reader edited: the warm pass recomputes it, and must refuse its undeclared read itself
    test-warm-undeclared-get-is-refused-reader-edited = {
      expr = refuses (sees (warmOverride engine (byGet 1 { }) "consumer" { w = 1; }));
      expected = true;
    };
    test-warm-undeclared-get-is-refused-not-stale-unprimed = {
      expr = refuses (sees (warmOverride engine (byGet 1 { }) "producer" { v = 9; }));
      expected = true;
    };
    test-control-warm-declared-get-equals-fresh-cold = {
      expr = [
        (sees (warmOverride engine (primed (byGet 1 edge)) "producer" { v = 9; }))
        (sees (byGet 9 edge))
      ];
      expected = [
        109
        109
      ];
    };
    # the arm: the edit moves the declared reader, so the parity cell is not two stale reads agreeing
    test-control-the-edit-moves-the-reader = {
      expr = sees (byGet 1 edge) != sees (byGet 9 edge);
      expected = true;
    };

    # the plane takes the relation from the seal and nowhere else: a ctx carrying none is refused,
    # since the evaluator would read its absence as "no contract" and serve the undeclared read
    test-a-ctx-without-the-contracted-relation-is-refused = {
      expr = refuses (
        sees (
          warmOverride engine ((byNode 1 edge) // { declaredDependencies = null; }) "consumer" { w = 1; }
        )
      );
      expected = true;
    };

    # and a ctx with no such field at all is refused the same way, catchably, rather than aborting
    test-a-ctx-with-no-relation-field-is-refused = {
      expr = refuses (
        sees (
          warmOverride engine (builtins.removeAttrs (byNode 1 edge) [ "declaredDependencies" ]) "consumer" {
            w = 1;
          }
        )
      );
      expected = true;
    };

    # ── 933zg: the warm accessor's `nodeData` is the cold accessor's ──
    test-warm-nodeData-reads-a-spawned-node = {
      expr = spawnWarm.accessor.nodeData "winnow";
      expected = spawnCold.accessor.nodeData "winnow";
    };
    test-control-spawned-nodeData-is-not-empty = {
      expr = spawnCold.accessor.nodeData "winnow";
      expected = {
        v = 7;
      };
    };
    test-warm-nodeData-sees-the-root-edit = {
      expr = (spawnWarm.accessor.nodeData "millstone").x;
      expected = 1;
    };
    test-warm-nodeData-through-a-driver-store = {
      expr = (storeOf spawnWarm.accessor).winnow;
      expected = (storeOf spawnCold.accessor).winnow;
    };
    test-warm-nodeData-refuses-an-unknown-id-as-cold-does = {
      expr = [
        (refuses (spawnCold.accessor.nodeData "ghost"))
        (refuses (spawnWarm.accessor.nodeData "ghost"))
      ];
      expected = [
        true
        true
      ];
    };
  };
}
