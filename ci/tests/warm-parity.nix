# Byte-parity over VARYING attribute grammars — the plane's defining property, run against a family
# of shapes rather than one fixture.
#
# A plane output is byte-identical to a cold evaluation of the same input. That is a definition and
# not a target: a plane that is fast and not byte-parity is not a faster plane, it is a wrong one.
# This suite is the standing instrument for it on the warm fold.
#
# Attribute DAGs are derived from integer seeds, never randomly: `a_i` reads `a_j` (j < i) iff
# (seed + 7i + 3j) mod 3 ≠ 0, so every generated grammar is acyclic by construction and varies with
# the seed.
#
# WHAT THIS SUITE STRENGTHENED, ON ARRIVAL FROM THE RETIRING LIBRARY, AND WHY IT HAD TO. The property
# that travelled here ran over a shape with exactly ONE node. That node is the edited one, so it is
# the seed of every cone, so it is always dirty, so it always recomputes — the property could not
# observe a reused value in any of its seeds, and would have read identically against a plane that
# reused nothing. A parity oracle whose every node recomputes is a parity oracle for the evaluator.
#
# The shape here carries a SECOND node that reads the first across a declared edge. It is not the
# edited node, so whether it is recomputed turns entirely on the cone being read correctly, and its
# value differs before and after the edit — so a cone that came back empty serves it stale and the
# equality fails. `test-cone-consumer-is-armed` states that dependence as its own cell rather than
# leaving it to be inferred from the parity result.
{
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride;

  modp = a: b: a - b * (a / b);
  range = n: builtins.genList (x: x) n;
  aName = i: "a${toString i}";
  n = 8;
  readsOf = seed: i: builtins.filter (j: modp (seed + 7 * i + 3 * j) 3 != 0) (range i);

  # a_i = i + (the edited node's base, at a_0) + the sum of what it reads. The base therefore flows
  # from a_0 up the whole DAG, so an edit to it moves every attribute of the edited node.
  attributesFor =
    seed:
    builtins.listToAttrs (
      map (i: {
        name = aName i;
        value =
          self: id:
          i
          + (if i == 0 then (self.node id).decls.base or 0 else 0)
          + builtins.foldl' (acc: j: acc + self.get id (aName j)) 0 (readsOf seed i);
      }) (range n)
    )
    // {
      # The cross-node read. On `node` it is a constant, so no cycle is formed. On `other` it reads
      # the edited node's TOP attribute and its BOTTOM one, and it needs both: the top exercises the
      # seeded DAG's depth, but the generator makes `a7` a leaf whenever (seed + 49) mod 3 == 0 —
      # true for two of the five seeds below, measured — and a leaf `a7` does not depend on the base
      # at all. `a0` IS the base, so summing it in makes the read move under every seed. Reading the
      # top alone left this suite's arm silently inert on 2/5 of its domain.
      crossed =
        self: id: if id == "other" then self.get "node" (aName (n - 1)) + self.get "node" (aName 0) else 0;
    };

  # The vocabulary these nodes' kinds are names in. A kind is a name in a REGISTERED vocabulary
  # rather than a free string, so the fixture registers the one kind it declares.
  hostKinds = genScope.mkKinds [ (genScope.mkKind { name = "host"; }) ];

  scopeFor =
    v:
    genScope.buildRoots {
      kinds = hostKinds;
      decls = {
        node.base = v;
        other = { };
      };
      types = {
        node = "host";
        other = "host";
      };
    };

  # `other` depends on `node`, so it is inside `node`'s reverse cone and must be recomputed.
  declaredDependencies = id: if id == "other" then [ "node" ] else [ ];

  mkCtx =
    seed: v:
    let
      scope = scopeFor v;
      attributes = attributesFor seed;
      parseParent = _: null;
      eval = genScope.eval { inherit scope attributes parseParent; };
    in
    {
      inherit
        scope
        attributes
        parseParent
        eval
        declaredDependencies
        ;
      # The node map, published under the name the seal publishes it under. The fixture mirrors
      # `foldEquations`' shape rather than inventing one: both fields, off the one record.
      roots = scope.nodes;
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

  seeds = [
    1
    2
    3
    4
    5
  ];

  warmed =
    seed:
    warmOverride engine (mkCtx seed 3) {
      id = "node";
      newDecls = {
        base = 9;
      };
    };
  probeNames = map aName (range n) ++ [ "crossed" ];
in
{
  flake.tests.warm-parity = {
    # Reps–Teitelbaum–Demers 1983 soundness: the warm result equals the cold evaluation with the
    # declaration pre-applied, on every attribute of every node, over every seeded grammar.
    # Soundness, not minimality — the cone is an over-approximation and this says nothing about how
    # little was recomputed.
    test-warm-equals-cold-over-seeds = {
      expr = builtins.all (
        seed:
        let
          w = warmed seed;
          c = mkCtx seed 9;
        in
        builtins.all (id: builtins.all (a: project w id a == project c id a) probeNames) [
          "node"
          "other"
        ]
      ) seeds;
      expected = true;
    };

    # THE ARM. `other` is not the edited node, so whether it recomputes turns entirely on the cone
    # being read correctly, and its `crossed` value moves with the edit under EVERY seed. Stated as
    # its own cell rather than left to be inferred: if the two sides were equal for a seed, the
    # parity cell would hold on that seed against a plane that reused everything, and nothing in a
    # green run would say so. It fired once already — see `crossed`'s own note.
    test-cone-consumer-is-armed = {
      expr = builtins.all (
        seed: project (mkCtx seed 3) "other" "crossed" != project (mkCtx seed 9) "other" "crossed"
      ) seeds;
      expected = true;
    };
  };
}
