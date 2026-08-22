# The warm override — arrived with the fold, and ARMED, because most of it could not fail as it
# stood.
#
# WHAT WAS VACUOUS AND WHY, measured rather than suspected. In the retiring library this fixture
# warm-served NOTHING. The incumbent filter kept an attribute only when its DECLARED stratum
# differed from the base one, every equation here is `synthesized`, and that kind's derived stratum
# IS the base — so the reuse set was empty for every node and every cell below passed against an
# evaluation that recomputed everything. `test-noncone-kept` in particular reads the same value
# whether the node was served or recomputed, so it is kept for its byte-parity content and is NOT
# the arm.
#
# The arms are the two decision cells: they read `isClean` and `reusable` as VALUES, so they observe
# the cone and the vocabulary directly rather than inferring them from an output that agrees either
# way. Under the retired classifier `reusable` was empty here; under the derived one it is the
# resolutional projection, which is what makes the second cell discriminating rather than
# descriptive. The cell that distinguishes a SERVED value from a recomputed one by its value alone
# is in `warm-override-cross-node.nix`, where a stale read is observable.
{
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride warmDecision;

  # The vocabulary these nodes' kinds are names in. A kind is a name in a REGISTERED vocabulary
  # rather than a free string, so the fixture registers the one kind it declares.
  hostKinds = genScope.mkKinds [ (genScope.mkKind { name = "host"; }) ];

  mkScope =
    cv:
    genScope.buildRoots {
      kinds = hostKinds;
      parentGraph = genScope.edge "child" "parent";
      decls = {
        parent = {
          v = 10;
        };
        child = {
          v = cv;
        };
      };
      types = {
        parent = "host";
        child = "host";
      };
    };
  attributes = {
    self-v = self: id: (self.node id).decls.v;
    plus-one = self: id: self.get id "self-v" + 1;
    imports = _self: _id: [ ];
    # A name inside the reserved structural namespace. It exists to be EXCLUDED: the evaluator
    # always recomputes it and never offers it for reuse, so it is the negative half of the
    # vocabulary cell below.
    edges-owns = _self: _id: [ ];
  };

  # A resolved context, assembled here rather than taken from the retiring library — which pins this
  # library and therefore cannot be pinned back. The fold reads exactly these fields.
  mkCtx =
    {
      scope,
      parseParent ? (_: null),
      declaredDependencies ? (_: [ ]),
    }:
    let
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

  pp = scope: id: scope.nodes.${id}.parent or null;
  scope = mkScope 1;
  ctx = mkCtx {
    inherit scope;
    parseParent = pp scope;
  };
  edited = warmOverride engine ctx {
    id = "child";
    newDecls = {
      v = 5;
    };
  };
in
{
  flake.tests.warm-override = {
    # Byte-identical (Reps–Teitelbaum–Demers 1983 soundness): the warm result equals a fresh cold
    # evaluation with the declaration pre-applied. Soundness, not minimality — the cone is an
    # over-approximation and this says nothing about how little was recomputed.
    test-override-byte-identical = {
      expr =
        let
          fresh = mkCtx {
            scope = mkScope 5;
            parseParent = pp (mkScope 5);
          };
        in
        project edited "child" "plus-one" == project fresh "child" "plus-one";
      expected = true;
    };

    # The changed node re-derives to the new declaration.
    test-override-new-value = {
      expr = project edited "child" "plus-one";
      expected = 6;
    };

    # A node outside the changed node's reverse cone keeps its value. NOT an arm — see the header:
    # a recompute of `parent` yields 11 as well.
    test-noncone-kept = {
      expr = project edited "parent" "plus-one";
      expected = 11;
    };

    # ARM 1 — the cone, read as a value. `child` is the seed and is dirty; `parent` is outside its
    # reverse cone under the empty declared-edge relation and is clean. Both directions in one cell,
    # so a decision that called everything dirty and one that called everything clean each fail.
    test-decision-cone = {
      expr =
        let
          d = warmDecision {
            inherit (ctx) accessor;
            prior = ctx.eval.facade;
          } [ "child" ];
        in
        {
          child = d.isClean "child";
          parent = d.isClean "parent";
        };
      expected = {
        child = false;
        parent = true;
      };
    };

    # ARM 2 — the reuse vocabulary is the evaluator's resolutional projection, not a declared
    # stratum. `edges-owns` is inside the reserved structural namespace and must be absent;
    # `plus-one` is outside it and must be present. Under the retired declared-stratum filter this
    # list was EMPTY for this fixture, so the cell separates the two classifiers rather than
    # restating one of them.
    test-decision-vocabulary = {
      expr =
        let
          d = warmDecision {
            inherit (ctx) accessor;
            prior = ctx.eval.facade;
          } [ "child" ];
          names = d.reusable "parent";
        in
        {
          serves-resolutional = builtins.elem "plus-one" names;
          withholds-structural = builtins.elem "edges-owns" names;
        };
      expected = {
        serves-resolutional = true;
        withholds-structural = false;
      };
    };

    # An edit that moves an EDGE is refused: the cone that authorised the decision was read over the
    # topology the edit reshapes.
    test-edge-move-throws = {
      expr =
        (builtins.tryEval (
          warmOverride engine ctx {
            id = "child";
            newDecls = {
              includes = [ "other" ];
            };
          }
        )).success;
      expected = false;
    };

    # The fold works over a CYCLIC declared-edge relation: `dependentsOf` is cycle-safe and the memo
    # ctx the fold attaches is lazy, so the store's node-cycle check is never reached.
    test-cyclic-override-ok = {
      expr =
        let
          cctx = mkCtx {
            inherit scope;
            parseParent = pp scope;
            declaredDependencies = id: if id == "child" then [ "parent" ] else [ "child" ];
          };
        in
        project (warmOverride engine cctx {
          id = "child";
          newDecls = {
            v = 7;
          };
        }) "child" "plus-one";
      expected = 8;
    };

    # The memo ctx the fold attaches is LAZY on the warm path and is a real ctx when forced: its
    # store is keyed by the evaluation's own nodes. Forcing it here is what makes the laziness cell
    # above mean something — an unforced field is trivially cycle-safe.
    test-builtctx-forces-over-the-warm-eval = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames edited.builtCtx.store);
      expected = [
        "child"
        "parent"
      ];
    };
  };
}
