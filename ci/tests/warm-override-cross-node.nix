# The cross-node warm-serve path — and the one cell in this repository that separates a SERVED
# value from a recomputed one by its value alone.
#
# A `consumer` node reads a `producer` node's resolutional attribute. The plane reads the cone from
# the DECLARED edge relation, so soundness holds exactly when that relation over-declares the
# cross-node read:
#
#   declared consumer→producer  ⇒ consumer is in the cone, re-derives, byte-identical to cold
#   relation empty              ⇒ consumer is outside the cone, is CLEAN, and is served its stale
#                                 prior — 101 rather than 109
#
# The second is the witness. It is the only assertion here that fails against an evaluator that
# warm-serves nothing at all, which is why the suite carries it rather than only the agreeable half:
# an over-declaration contract with no cell for the under-declared case documents a rule whose
# violation has never been observed.
{
  lib,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride;

  mkRoots =
    v:
    genScope.buildNodes {
      importGraph = genScope.edge "consumer" "producer";
      decls = {
        producer.v = v;
        consumer = { };
      };
      types = {
        producer = "host";
        consumer = "host";
      };
    };
  attributes = {
    imports = self: id: (self.node id).decls.__edges.I or [ ];
    p-val = self: id: (self.node id).decls.v or 0;
    # The cross-node read: a resolutional attribute of one node reading a resolutional attribute of
    # another. Nothing in the substrate declares this edge; the caller's relation must.
    sees = self: id: if id == "consumer" then (self.get "producer" "p-val") + 100 else 0;
  };

  mkCtx =
    { roots, declaredDependencies }:
    let
      parseParent = _: null;
      eval = genScope.eval { inherit roots attributes parseParent; };
    in
    {
      inherit
        roots
        attributes
        parseParent
        eval
        declaredDependencies
        ;
      accessor = {
        nodes = builtins.attrNames eval.allNodes;
        dependencies = declaredDependencies;
        parent = parseParent;
        nodeData = id: (eval.node id).decls or { };
      };
    };
  project =
    ctx: id: attr:
    ctx.eval.get id attr;
  bump =
    ctx:
    warmOverride engine ctx {
      id = "producer";
      newDecls = {
        v = 9;
      };
    };

  declaredDependencies = id: if id == "consumer" then [ "producer" ] else [ ];

  # (1) the read is declared — the consumer is in the producer's cone
  ctxD = mkCtx {
    roots = mkRoots 1;
    inherit declaredDependencies;
  };
  ctxD' = bump ctxD;
  freshD = mkCtx {
    roots = mkRoots 9;
    inherit declaredDependencies;
  };

  # (2) the read is NOT declared — the consumer is outside the cone and is served stale
  ctxN = mkCtx {
    roots = mkRoots 1;
    declaredDependencies = _: [ ];
  };
  ctxN' = bump ctxN;
in
{
  flake.tests.warm-override-cross-node = {
    # The edited node is a seed and always re-derives, whatever the edge relation says.
    test-producer-rederives = {
      expr = project ctxN' "producer" "p-val";
      expected = 9;
    };

    # Declared cross-edge: the consumer is in the cone and re-derives to the fresh value.
    test-declared-consumer-rederives = {
      expr = project ctxD' "consumer" "sees";
      expected = 109;
    };

    test-declared-byte-identical = {
      expr = project ctxD' "consumer" "sees" == project freshD "consumer" "sees";
      expected = true;
    };

    # THE WITNESS. Under-declared cross-edge: the consumer is clean, `sees` is resolutional, and the
    # value served is the PRIOR one — 100 + the old v=1. A recompute would answer 109. Reuse is
    # observable here and nowhere else in this suite.
    test-undeclared-serves-stale = {
      expr = project ctxN' "consumer" "sees";
      expected = 101;
    };
  };
}
