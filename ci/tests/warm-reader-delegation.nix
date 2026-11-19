# THE WARM PLANE OVER A READER HANDED OUT AS A VALUE — producer-bounded delegation (den-hoag-9pt45).
#
# A declared node's attribute may return its own reader, directly, in a record or list, or captured
# by a closure, and another node may forward it. A consumer holding it reads what the producer
# declared, through its own declared path (gen-scope's `reader-delegation` cells, cold). Here the
# producer's target `kid` is edited and the plane's own warm fold (`warmOverride`: its decision is
# the reverse cone of the edit over the sealed union relation) must serve every route what a fresh
# cold fold of the edited scope serves. The cone is transitive, so every node on the declared path
# from the consumer to `kid` is dirty, the producer included; a decision that reused the producer
# would serve the handed reader's prior answer. That arm is built below as the live control: a hand
# decision recomputing only `kid` and the consumers reads stale, so the parity cells can fail.
#
# The refusals hold warm: the consumer's own undeclared read, and a target the producer did not
# declare. The nta route (a host's reader in a child's seed) is NOT claimed fresh: it is stale with
# no reader at all (den-hoag-h7w6l), and no cell here reads it.
{
  graph,
  genMemo,
  genScope,
  engine,
  ...
}:
let
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  R = "REFUSED";
  res = name: compute: {
    inherit name compute;
    kind = "synthesized";
    readsAttrs = [ ];
    stratum = "resolution";
  };
  rel = r: graph.mkDeclaredEdges (builtins.mapAttrs (_: map (graph.mkNodeRef (_: true))) r);
  consumers = [
    "cDirect"
    "cFwd"
    "cFwd2"
    "cRec"
    "cFn"
    "cOwn"
    "cBeyond"
    "cKid"
  ];
  ids = [
    "producer"
    "relay"
    "relay2"
    "kid"
    "gk"
  ]
  ++ consumers;
  scopeAt =
    edits:
    genScope.buildRoots {
      kinds = genScope.mkKinds [ (genScope.mkKind { } "host") ];
      decls =
        builtins.listToAttrs (
          map (n: {
            name = n;
            value = { };
          }) ids
        )
        // {
          kid.v = 1;
          gk.v = 5;
        }
        // edits;
      types = builtins.listToAttrs (
        map (n: {
          name = n;
          value = "host";
        }) ids
      );
    };
  is =
    want: id: v:
    if id == want then v else null;
  val = self: k: self.get k "val";
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
    val = res "val" (self: id: (self.node id).decls.v or 0);
    leak = res "leak" (self: id: is "producer" id self);
    rec_ = res "rec_" (
      self: id:
      is "producer" id {
        inner.r = self;
        l = [ self ];
      }
    );
    fn = res "fn" (self: id: is "producer" id (k: val self k));
    fwd = res "fwd" (self: id: is "relay" id (self.get "producer" "leak"));
    fwd2 = res "fwd2" (self: id: is "relay2" id (self.get "relay" "fwd"));
    out = res "out" (
      self: id:
      let
        leak = self.get "producer" "leak";
      in
      if id == "cDirect" then
        {
          node = try (leak.node "kid").decls.v;
          get = try (leak.get "kid" "val");
        }
      else if id == "cFwd" then
        { get = try ((self.get "relay" "fwd").get "kid" "val"); }
      else if id == "cFwd2" then
        { get = try ((self.get "relay2" "fwd2").get "kid" "val"); }
      else if id == "cRec" then
        {
          inner = try ((self.get "producer" "rec_").inner.r.get "kid" "val");
          list = try ((builtins.head (self.get "producer" "rec_").l).get "kid" "val");
        }
      else if id == "cFn" then
        { call = try ((self.get "producer" "fn") "kid"); }
      else if id == "cOwn" then
        { get = try (self.get "kid" "val"); }
      else if id == "cBeyond" then
        { get = try (leak.get "gk" "val"); }
      else if id == "cKid" then
        { get = try (self.get "kid" "val"); }
      else
        null
    );
  };
  live = rel {
    producer = [ "kid" ];
    relay = [ "producer" ];
    relay2 = [ "relay" ];
    cDirect = [ "producer" ];
    cFwd = [ "relay" ];
    cFwd2 = [ "relay2" ];
    cRec = [ "producer" ];
    cFn = [ "producer" ];
    cOwn = [ "producer" ];
    cBeyond = [ "producer" ];
    cKid = [ "kid" ];
  };
  fold =
    relation: edits:
    genScope.foldEquations { } {
      scope = scopeAt edits;
      schedule = { inherit equations; };
      declaredDependencies = relation;
      parseParent = _: null;
    };
  rows =
    ev:
    builtins.listToAttrs (
      map (c: {
        name = c;
        value = try (ev.get c "out");
      }) consumers
    );

  cold = fold live { };
  fresh = rows (fold live { kid.v = 9; }).eval;
  warm = rows (genMemo.warmOverride engine cold "kid" { v = 9; }).eval;
  coldRows = rows cold.eval;
  # the live control: a decision that reuses the producer and the forwarders
  hand = rows (
    genScope.evalWarm
      {
        parseParent = _: null;
        declaredDependencies = live;
      }
      {
        scope = scopeAt { kid.v = 9; };
        inherit (cold) attributes;
        prior = cold.eval;
        decision = genScope.mkDecision {
          isClean = n: !(builtins.elem n ([ "kid" ] ++ consumers));
          reusable = cold.eval.facade.resolutional;
        };
      }
  );
  emptyCold = fold (rel { }) { };
  routes = [
    "cDirect"
    "cFwd"
    "cFwd2"
    "cRec"
    "cFn"
  ];
  pick =
    t:
    builtins.listToAttrs (
      map (c: {
        name = c;
        value = t.${c};
      }) routes
    );
  every = v: builtins.mapAttrs (_: builtins.mapAttrs (_: _: v)) (pick coldRows);
in
{
  flake.tests.warm-reader-delegation = {
    # every delegated route: cold 1, warm = fresh = 9
    test-control-every-route-reads-the-producers-target-cold = {
      expr = pick coldRows;
      expected = every 1;
    };
    test-every-delegated-route-warm-equals-fresh-cold = {
      expr = {
        warm = pick warm;
        fresh = pick fresh;
      };
      expected = {
        warm = every 9;
        fresh = every 9;
      };
    };
    # the instrument can fail: reusing the producer and the forwarders serves the prior answer
    test-control-a-decision-reusing-the-producer-serves-stale = {
      expr = pick hand;
      expected = every 1;
    };
    # the plane's cone carries the producer and both forwarders, though none is the edit
    test-the-warm-cone-dirties-the-producer-and-the-forwarders = {
      expr =
        let
          dn = genMemo.warmDecision cold.accessor cold.eval.facade [ "kid" ];
        in
        map dn.isClean [
          "producer"
          "relay"
          "relay2"
          "gk"
        ];
      expected = [
        false
        false
        false
        true
      ];
    };
    # a plain declared read moves with the edit too
    test-control-the-own-declared-read-warm-equals-fresh = {
      expr = [
        warm.cKid
        fresh.cKid
      ];
      expected = [
        { get = 9; }
        { get = 9; }
      ];
    };
    # the refusals hold warm: own undeclared read; a target the producer did not declare
    test-warm-own-undeclared-read-is-refused = {
      expr = warm.cOwn;
      expected.get = R;
    };
    test-warm-a-target-the-producer-did-not-declare-is-refused = {
      expr = warm.cBeyond;
      expected.get = R;
    };
    test-warm-the-empty-relation-refuses-every-route = {
      expr = pick (rows (genMemo.warmOverride engine emptyCold "kid" { v = 9; }).eval);
      expected = every R;
    };
  };
}
