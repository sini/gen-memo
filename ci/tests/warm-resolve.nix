# The batch warm fold. N edits take ONE union cone and ONE evaluation, and the result is required to
# agree with two independent references: the chained single-edit sequence, and a fresh cold
# evaluation with every edit pre-applied.
#
# The batch takes the edits themselves rather than a list of changed ids: a pure batch has to carry
# the data-change payload, and a bare id list cannot.
{
  lib,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  inherit (genMemo) warmOverride warmResolve;

  mkRoots =
    av: bv:
    genScope.buildNodes {
      decls = {
        a = {
          v = av;
        };
        b = {
          v = bv;
        };
      };
      types = {
        a = "host";
        b = "host";
      };
    };
  attributes = {
    self-v = self: id: (self.node id).decls.v;
    plus-one = self: id: self.get id "self-v" + 1;
    imports = _self: _id: [ ];
  };

  mkCtx =
    roots:
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
        ;
      declaredEdges = _: [ ];
      accessor = {
        nodes = builtins.attrNames eval.allNodes;
        edges = _: [ ];
        parent = parseParent;
        nodeData = id: (eval.node id).decls or { };
      };
    };
  project =
    ctx: id: attr:
    ctx.eval.get id attr;

  ctx = mkCtx (mkRoots 1 2);
  edits = {
    a = {
      v = 5;
    };
    b = {
      v = 6;
    };
  };
  batch = warmResolve engine ctx { inherit edits; };
  probe = c: [
    (project c "a" "plus-one")
    (project c "b" "plus-one")
  ];
in
{
  flake.tests.warm-resolve = {
    # The batch equals the chained single-edit sequence over the same edits.
    test-batch-eq-chained = {
      expr =
        let
          chained =
            warmOverride engine
              (warmOverride engine ctx {
                id = "a";
                newDecls = {
                  v = 5;
                };
              })
              {
                id = "b";
                newDecls = {
                  v = 6;
                };
              };
        in
        probe batch == probe chained;
      expected = true;
    };

    # The batch equals a fresh cold evaluation with every edit pre-applied.
    test-batch-eq-fresh = {
      expr = probe batch == probe (mkCtx (mkRoots 5 6));
      expected = true;
    };

    # Stated absolutely as well as relatively: two equalities both hold trivially if the fold
    # returns its input unchanged, and this cell is what says the values moved.
    test-batch-values = {
      expr = probe batch;
      expected = [
        6
        7
      ];
    };

    # An edge-move ANYWHERE in the batch is refused, not just at its head.
    test-batch-edge-move-throws = {
      expr =
        (builtins.tryEval (
          warmResolve engine ctx {
            edits = {
              a = {
                v = 5;
              };
              b = {
                includes = [ "x" ];
              };
            };
          }
        )).success;
      expected = false;
    };
  };
}
