# The cross-node warm-serve path, and the cells that separate a SERVED value from a recomputed one.
#
# A `consumer` node reads a `producer` node's resolutional attribute. The plane reads the cone from
# the declared edge relation, and the warm pass is armed with that relation, as the cold fold is:
#
#   declared consumer→producer  ⇒ consumer is in the cone, re-derives, byte-identical to cold
#   relation empty              ⇒ the `self.get` read is REFUSED, warm as cold, rather than served
#                                 its stale prior
#
# The guard covers the reader's `self.node`, `self.get` and `self.getRepresentative`. A body reading
# another node through a different field of its reader is not refused and can still be served
# stale; this suite seeds `self.get` only.
#
# Reuse is witnessed without an under-declaration: the prior is evaluated under a program whose
# `tag` differs from the one the warm pass runs, so a node outside the cone answers the PRIOR's tag
# when it is served and the program's when it is recomputed. Without that cell a plane that served
# nothing would pass every other one here. No `foldEquations` seals such a ctx: it is a fixture for
# the reuse fact, not an example of a seal.
{
  genMemo,
  genScope,
  engine,
  fx,
  ...
}:
let
  inherit (genMemo) warmOverride;

  # The vocabulary these nodes' kinds are names in. A kind is a name in a REGISTERED vocabulary
  # rather than a free string, so the fixture registers the one kind it declares.
  hostKinds = genScope.mkKinds [ (genScope.mkKind { } "host") ];

  mkScope =
    v:
    genScope.buildRoots {
      kinds = hostKinds;
      importGraph = genScope.edge {
        from = "consumer";
        to = "producer";
      };
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
    # ★ `children` IS DECLARED, NOT OMITTED (den-hoag-6imt). gen-scope refuses a descent from an
    # evaluation that declares no containment relation. This scope declares no `parentGraph` — its
    # only relation is the import edge above — so every node is a root and `{ }` is the true answer
    # rather than a silenced one.
    children = _self: _id: { };
    imports = self: id: (self.node id).decls.__edges.I or [ ];
    p-val = self: id: (self.node id).decls.v or 0;
    # The cross-node read: a resolutional attribute of one node reading a resolutional attribute of
    # another. Nothing in the substrate declares this edge; the caller's relation must.
    sees = self: id: if id == "consumer" then (self.get "producer" "p-val") + 100 else 0;
    tag = _self: _id: "program";
  };

  mkCtx =
    {
      scope,
      declaredDependencies,
      priorAttributes ? attributes,
    }:
    let
      parseParent = _: null;
      contracted = fx.contractRelation scope declaredDependencies;
      eval = genScope.eval {
        inherit parseParent;
        declaredDependencies = contracted;
      } priorAttributes scope;
    in
    {
      inherit
        scope
        attributes
        parseParent
        eval
        ;
      declaredDependencies = contracted;
      # The node map, published under the name the seal publishes it under. The fixture mirrors
      # `foldEquations`' shape rather than inventing one: both fields, off the one record.
      roots = scope.nodes;
      accessor = {
        nodes = builtins.attrNames eval.allNodes;
        dependencies = contracted.dependencies;
        parent = parseParent;
        nodeData = id: (eval.node id).decls or { };
      };
    };
  project =
    ctx: id: attr:
    ctx.eval.get id attr;
  bump =
    ctx:
    warmOverride engine ctx "producer" {
      v = 9;
    };

  declaredDependencies = id: if id == "consumer" then [ "producer" ] else [ ];

  # (1) the read is declared — the consumer is in the producer's cone
  ctxD = mkCtx {
    scope = mkScope 1;
    inherit declaredDependencies;
  };
  ctxD' = bump ctxD;
  freshD = mkCtx {
    scope = mkScope 9;
    inherit declaredDependencies;
  };

  # (2) the read is NOT declared — refused, warm as cold
  ctxN = mkCtx {
    scope = mkScope 1;
    declaredDependencies = _: [ ];
  };
  ctxN' = bump ctxN;

  # (3) the reuse witness: the prior ran a program whose `tag` disagrees with the one the warm pass runs
  ctxR = mkCtx {
    scope = mkScope 1;
    inherit declaredDependencies;
    priorAttributes = attributes // {
      tag = _self: _id: "prior";
    };
  };
  # the edit lands on the consumer, whose reverse cone is itself, so the producer is clean
  ctxR' = warmOverride engine ctxR "consumer" { w = 1; };
  refuses = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
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

    # Under-declared cross-edge: the read is refused on the cold fold and on the warm pass alike.
    test-undeclared-read-is-refused-cold = {
      expr = refuses (project ctxN "consumer" "sees");
      expected = true;
    };
    test-undeclared-read-is-refused-warm-not-served-stale = {
      expr = refuses (project ctxN' "consumer" "sees");
      expected = true;
    };

    # THE REUSE WITNESS. The consumer is edited and recomputes; the producer is outside its cone and
    # is served. `tag` reads nothing, so a served `tag` is the prior program's and a recomputed one
    # the warm pass's: the same ctx shows both arms.
    test-a-clean-node-is-served-its-prior = {
      expr = [
        (project ctxR' "consumer" "tag")
        (project ctxR' "producer" "tag")
      ];
      expected = [
        "program"
        "prior"
      ];
    };
  };
}
