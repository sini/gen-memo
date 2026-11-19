# The grown-child fixture shared by `tests/warm-grown-child.nix` (the warm plane) and
# `tests-error.nix` (the acyclic consumer's refusal, read as a message), so the relation a refusal is
# earned on and the relation the warm cells answer over are one value. Outside `tests/` so the
# harness does not collect it as a test module.
{
  graph,
  genMemo,
  genScope,
  engine,
  prelude,
}:
let
  inherit (builtins)
    head
    isAttrs
    attrNames
    filter
    elemAt
    ;
  addr = def: at: {
    attr = "defs";
    inherit def at;
  };
  ntaK =
    host: name: key:
    genScope.mintNtaId {
      inherit host name key;
      group = "g";
    };
  nta = host: name: ntaK host name "k";
  grow =
    self: id:
    let
      d = self.get id "defs";
    in
    if d != [ ] && isAttrs (head d) && head d ? s then { g.k = [ (addr 0 [ "s" ]) ]; } else { };
  grow2 =
    self: id:
    let
      d = self.get id "defs";
    in
    if d != [ ] && isAttrs (head d) && head d ? s then
      {
        g = {
          k = [ (addr 0 [ "s" ]) ];
          k2 = [ (addr 0 [ "s" ]) ];
        };
      }
    else
      { };
  copy = h: id: { "${id}-c".decls.defs = (h.node id).decls.defs; };
  kinds = genScope.mkKinds [
    (genScope.mkKind { } "plain")
    (genScope.mkKind { nta.x = grow; } "host")
    (genScope.mkKind { nta.x = grow2; } "host2")
    (genScope.mkKind {
      nta.y = grow;
      ntaOnDemand = [ "y" ];
    } "lazy")
    (genScope.mkKind {
      below = [ "plain" ];
      spawns.plain = copy;
    } "sp")
    (genScope.mkKind {
      below = [ "plain" ];
      spawns.plain = h: id: { "${id}-c".decls.defs = (h.node "x").decls.defs; };
    } "spx")
    (genScope.mkKind {
      below = [ "sp" ];
      spawns.sp = copy;
    } "sp2")
  ];
  res = name: compute: {
    inherit name compute;
    kind = "synthesized";
    readsAttrs = [ ];
    stratum = "resolution";
  };
  rootsParent = {
    "p@c" = "p";
  };
  parseParent =
    id:
    let
      d = genScope.decodeNta id;
      m = builtins.match "(.*)-c" id;
    in
    if d != null then
      d.host
    else if m != null then
      head m
    else
      rootsParent.${id} or null;
  hChild = nta "h" "x";
  zChild = nta "r2" "x";
  hrChild = nta "hr" "x";
  aeChild = nta "r2b" "x";
  xk = ntaK "xh" "x" "k";
  has = variant: shape: builtins.elem shape variant;
  equations = variant: roots: {
    children = {
      name = "children";
      kind = "nta";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _: id: prelude.filterAttrs (_: n: (n.parent or null) == id) roots.nodes;
    };
    imports = {
      name = "imports";
      kind = "synthesized";
      readsAttrs = [ ];
      stratum = "structural";
      compute = _: _: [ ];
    };
    defs = res "defs" (
      self: id:
      let
        d = (self.node id).decls;
      in
      if d ? seed then map (e: e.value) d.seed else d.defs or [ ]
    );
    hostDefs = res "hostDefs" (
      self: id: if id == hChild && has variant "c6" then self.get "h" "defs" else null
    );
    hostAgg = res "hostAgg" (
      self: id: if id == "hr" && has variant "hr" then self.getNta "x" "g" "k" "defs" else null
    );
    zRead = res "zRead" (
      self: id:
      if id == "z" then
        self.get zChild "defs"
      else if id == "zb" && has variant "ae" then
        self.get aeChild "defs"
      else
        null
    );
    aRead = res "aRead" (
      self: id: if id == "r2b" && has variant "ae" then self.get "zb" "zRead" else null
    );
    zDep = res "zDep" (self: id: if id == xk then self.get "xz" "defs" else null);
  };
  declsAt =
    e:
    {
      r.defs = [ { s = 1; } ];
      n.defs = [ { s.s = 1; } ];
      o.defs = [ { s = 1; } ];
      q.defs = [ 1 ];
      w.defs = [ 0 ];
      x.defs = [ 1 ];
      h.defs = [ { s = 1; } ];
      u.defs = [ { s = 7; } ];
      p.defs = [ 1 ];
      "p@c".defs = [ 5 ];
      d3.defs = [ { s.s.s = 1; } ];
      ss.defs = [ 1 ];
      r2.defs = [ { s = 1; } ];
      z.defs = [ 0 ];
      hr.defs = [ { s = 1; } ];
      xh.defs = [ { s = 1; } ];
      xz.defs = [ 4 ];
      r2b.defs = [ { s = 1; } ];
      zb.defs = [ 0 ];
    }
    // e;
  types = {
    r = "host";
    n = "host";
    o = "lazy";
    q = "sp";
    w = "spx";
    x = "plain";
    h = "host";
    u = "host";
    p = "plain";
    "p@c" = "plain";
    d3 = "host";
    ss = "sp2";
    r2 = "host";
    z = "plain";
    hr = "host";
    xh = "host2";
    xz = "plain";
    r2b = "host";
    zb = "plain";
  };
  scopeAt =
    e:
    genScope.buildRoots {
      inherit kinds types;
      decls = declsAt e;
      parentGraph = genScope.overlay (genScope.vertex "r") (
        genScope.edge {
          from = "p@c";
          to = "p";
        }
      );
    };
  declaredFor =
    variant:
    graph.mkDeclaredEdges (
      builtins.mapAttrs (_: map (graph.mkNodeRef (_: true))) (
        {
          w = [ "x" ];
          z = [ zChild ];
          ${xk} = [ "xz" ];
        }
        // (if has variant "c6" then { ${hChild} = [ "h" ]; } else { })
        // (if has variant "hr" then { hr = [ hrChild ]; } else { })
        // (
          if has variant "ae" then
            {
              r2b = [ "zb" ];
              zb = [ aeChild ];
            }
          else
            { }
        )
      )
    );
  foldAt =
    variant: e:
    let
      s = scopeAt e;
    in
    genScope.foldEquations { } {
      scope = s;
      schedule.equations = equations variant s;
      inherit parseParent;
      declaredDependencies = declaredFor variant;
    };
  # Every in-unit read except AE: the relation is acyclic, so every acyclic consumer accepts it.
  acyclicVariant = [
    "c6"
    "hr"
  ];
  cold = foldAt acyclicVariant { };
  # One edit at a root, read warm and fresh.
  warmFresh =
    variant: edit: reads:
    let
      id0 = head (attrNames edit);
      c = foldAt variant { };
      warm = (genMemo.warmOverride engine c id0 edit.${id0}).eval;
      fresh = (foldAt variant edit).eval;
      rd = ev: map (pr: ev.get (head pr) (elemAt pr 1)) reads;
    in
    {
      warm = rd warm;
      fresh = rd fresh;
    };
  # The cold value first, so a cell whose edit moves nothing cannot pass.
  moves =
    variant: edit: reads:
    let
      r = warmFresh variant edit reads;
      c = foldAt variant { };
    in
    {
      inherit (r) warm;
      equal = r.warm == r.fresh;
      moved = map (pr: c.eval.get (head pr) (elemAt pr 1)) reads != r.fresh;
    };
  dirtyFor =
    id0:
    let
      d = genMemo.warmDecision cold.accessor cold.eval.facade [ id0 ];
    in
    filter (i: !(d.isClean i)) cold.accessor.nodes;
  # gen-memo's acyclic build over a variant's cold relation, its store forced.
  buildOf =
    variant:
    let
      store =
        (genMemo.build { } engine {
          inherit (foldAt variant { }) accessor;
          recompute =
            acc': _store: id:
            acc'.nodeData id;
          hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);
        }).store;
    in
    builtins.deepSeq store store;
  builds = variant: (builtins.tryEval (buildOf variant)).success;
  fresh = {
    equal = true;
    moved = true;
  };
  parity = r: { inherit (r) equal moved; };
in
{
  inherit
    nta
    hChild
    zChild
    hrChild
    aeChild
    xk
    foldAt
    acyclicVariant
    cold
    moves
    dirtyFor
    buildOf
    builds
    fresh
    parity
    ;
}
