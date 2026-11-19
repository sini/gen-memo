# A CLEAN QUOTIENT ATTRIBUTE IS SERVED WARM, TAGGED, AS COLD SERVES IT (den-hoag-fja3w).
#
# `q1` converges a `circular` attribute over a `quotient = true` carrier, and `q2` reads it through
# `getRepresentative` across a declared edge. The edit (`k2.v`) is unrelated to both, so the decision
# calls them clean and the evaluator serves `rep` from the prior through the demand form its
# declaration takes, `getRepresentative`. The prior that serves it is the prior EVALUATION; the plane's
# own read is the facade, whose key set stays `get`, `nodeIds`, `resolutional`. A fold that hands the
# facade as the evaluator's prior aborts here with `attribute 'getRepresentative' missing`, which no
# `tryEval` catches.
#
# The reuse-kept control: the dirty set is the edited node alone and `rep` is in `q1`'s served set, so
# the parity cells read the served path, not a recompute. The dirty control: an edit to `q1` itself
# recomputes, and moves the representative.
{
  graph,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  res = name: compute: {
    inherit name compute;
    kind = "synthesized";
    readsAttrs = [ ];
    stratum = "resolution";
  };
  carrier = {
    bottom = 0;
    leq = a: b: a <= b;
    height = 50;
    quotient = true;
  };
  ids = [
    "q1"
    "q2"
    "k2"
  ];
  scopeAt =
    edits:
    genScope.buildRoots {
      kinds = genScope.mkKinds [ (genScope.mkKind { } "plain") ];
      types = builtins.listToAttrs (
        map (n: {
          name = n;
          value = "plain";
        }) ids
      );
      decls = {
        q1.v = 1;
        q2.v = 0;
        k2.v = 2;
      }
      // edits;
    };
  equations = {
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
    v = res "v" (self: id: (self.node id).decls.v or 0);
    rep = res "rep" (
      genScope.circular { inherit carrier; } (
        self: id: _prev:
        (self.node id).decls.v or 0
      )
    );
    peerRep = res "peerRep" (self: id: if id == "q2" then self.getRepresentative "q1" "rep" else null);
  };
  fold =
    edits:
    genScope.foldEquations { } {
      scope = scopeAt edits;
      schedule = { inherit equations; };
      declaredDependencies = graph.mkDeclaredEdges { q2 = [ (graph.mkNodeRef (_: true) "q1") ]; };
      parseParent = _: null;
    };
  cold = fold { };
  reads = ev: {
    repQ1 = ev.getRepresentative "q1" "rep";
    peerRepQ2 = ev.get "q2" "peerRep";
  };
  warmAt = id: decls: (genMemo.warmOverride engine cold id decls).eval;
in
{
  flake.tests.warm-quotient-prior = {
    test-a-clean-quotient-attribute-is-served-warm-as-cold-serves-it = {
      expr = reads (warmAt "k2" { v = 9; });
      expected = reads (fold { k2.v = 9; }).eval;
    };
    test-the-served-representative-is-tagged = {
      expr = (warmAt "k2" { v = 9; }).getRepresentative "q1" "rep";
      expected = {
        _type = "gen-scope/quotient-representative";
        representative = 1;
      };
    };
    test-the-quotient-node-is-clean-and-rep-is-served = {
      expr = {
        dirty = builtins.filter (
          i: !((genMemo.warmDecision cold.accessor cold.eval.facade [ "k2" ]).isClean i)
        ) cold.accessor.nodes;
        servesRep = builtins.elem "rep" ((warmAt "k2" { v = 9; }).served "q1");
      };
      expected = {
        dirty = [ "k2" ];
        servesRep = true;
      };
    };
    test-a-dirty-quotient-attribute-recomputes-and-moves = {
      expr = reads (warmAt "q1" { v = 5; });
      expected = reads (fold { q1.v = 5; }).eval;
    };
    test-the-plane-reads-the-three-name-facade = {
      expr = builtins.attrNames cold.eval.facade;
      expected = [
        "get"
        "nodeIds"
        "resolutional"
      ];
    };
  };
}
