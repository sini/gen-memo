# hash — internal content-hash guarding, shared by build and the override cone.
#
# Mokhov 2018 assumes a TOTAL `hash :: Hashable v => v -> Hash v` (§3.1) feeding
# the verifying trace (§4.2.2). Nix `hashOf` is PARTIAL on function-bearing values
# (not toJSON-able; the error is uncatchable by tryEval) — no Hashable instance.
# Modelled structurally: such values get `hash = null` and are conservatively
# always-dirty (never false-clean). ★ THE NULL RULE ITSELF HAS NO PAPER BEHIND IT —
# it is an operational Nix fact and not a theorem, and the disclaimer travels with
# the rule wherever the rule goes.
#
# ★★ THERE IS A SECOND PARTIALITY: a value whose walk does not end. A self-loop, a
# two-cycle or an unboundedly generated value is an ordinary readable Nix value with no
# finite walk, and an unbounded walker meets the evaluator's call-depth ceiling on it —
# an abort `tryEval` does not contain, where the cold evaluation it decides for has a
# value. Two constructions meet it, both at the hash boundary, and `hashGuarded` is the
# only application site of either, so the ten call sites that hand it a whole node value
# are covered at one place:
#   - a DERIVATION is the ordinary member of the class (a config value containing a
#     package), and `project` below normalises it to a tag before anything descends;
#   - EVERYTHING ELSE is met by a BOUNDED walk whose exhaustion lands on the null rule
#     above — the same conservative side, so the plane keeps deciding and its answer is
#     the cold one.
#
# WHY A PROJECTION AND NOT A REFUSAL. A config value containing a package is the
# ORDINARY shape, so a plane that refused derivation-valued nodes would refuse
# ordinary configurations, and a construction whose correct behaviour is to reject
# the common case is not a construction. The value is CARRIABLE — its drvPath
# resolves fine — it is only UNHASHABLE.
#
# NOT PART OF THE PUBLIC SURFACE, deliberately. `lib/default.nix` does not fold this
# file in; the files that need the guards import it directly. That is the state this
# content shipped in and it is kept rather than widened in passing: the plane hashes
# for its own reuse decision, and the evaluator it decides for is owed no hash surface
# at all. Putting any of these on the export list would be a new surface arriving under
# cover of a move — the projection least of all: it is an admission-time normalisation
# internal to hashing, not a value transformation the plane offers anyone.
{ ... }:
let
  # THE TWO BOUNDS. Both are engine constants; neither is a consumer field (den-hoag-5ahw, OQ-1
  # ruled (i)). Past either one the walk ends `exhausted` and the value is always-dirty, which
  # changes what the plane COSTS and never what it ANSWERS. Their derivations are recorded in the
  # README (Limitations) and are re-derived when an evaluator or the walk changes.
  #
  # `maxDepth` (D) is a real ceiling. The walk below and the `hashOf` it certifies for (the plane's
  # own is `toJSON`) each spend about one evaluator call frame per level, against a default
  # `max-call-depth` of 10000. D takes half of that budget and leaves the other half to whatever
  # called the plane. ONE D for upstream Nix, Determinate and Lix.
  #
  # `maxPositions` (B) is a cost number and nothing else: the most positions one walk visits.
  #
  # ★ THE FALLBACK IS SILENT, and that is recorded rather than accepted: nothing tells a
  # consumer its node went always-dirty on a bound. `classify` names the reason and stays
  # internal (tests read it); emitting it is owed through the warned-outcome channel
  # `den-hoag-3yh6` ruled — the result carrying its own provenance — and is not built here.
  maxDepth = 5000;
  maxPositions = 32768;

  # An attrset the walk descends into: any attrset that is not a derivation. The walk reads the RAW
  # value and treats a derivation as a leaf, which is exactly where `project` stops, so it certifies
  # what `hashOf` will be handed without building the projection first — building it is what would
  # make a wide cycle cost B times its width. `? drvPath` goes first because it is the cheap test and
  # is false for nearly every attrset.
  isRecord = v: builtins.isAttrs v && !(v ? drvPath && isDrv v);
  hasContainer = xs: builtins.any isRecord xs || builtins.any builtins.isList xs;

  # One level per call: `front` holds the positions at nesting depth `k` (function-free, at least
  # one of them a container) and `n` counts the positions visited so far. Breadth-first, so the
  # walk's OWN call depth is its number of levels — at most D, never a function of B — and each
  # level is a few builtin passes. The next level is COUNTED before it is concatenated or forced,
  # and the count stops once it passes B, so a level of many wide containers costs Θ(B + its widest
  # container) rather than its full fan-out.
  descend =
    k: n: front:
    let
      kids =
        map builtins.attrValues (builtins.filter isRecord front) ++ builtins.filter builtins.isList front;
      n' = builtins.foldl' (s: c: if s > maxPositions then s else s + builtins.length c) n kids;
      next = builtins.concatLists kids;
    in
    if n' > maxPositions then
      "exhausted"
    else if builtins.any builtins.isFunction next then
      "function"
    else if !(hasContainer next) then
      "finite"
    else if k + 1 >= maxDepth then
      "exhausted"
    else
      descend (k + 1) n' next;

  # The root's own children are read without the level machinery: a value that misses the fast path
  # below most often holds a function there, or is wide there.
  fromRoot =
    cs:
    let
      n = 1 + builtins.length cs;
    in
    if n > maxPositions then
      "exhausted"
    else if builtins.any builtins.isFunction cs then
      "function"
    else if !(hasContainer cs) then
      "finite"
    else
      descend 1 n cs;
  walk =
    v:
    if builtins.isFunction v then
      "function"
    else if isRecord v then
      fromRoot (builtins.attrValues v)
    else if builtins.isList v then
      fromRoot v
    else
      "finite";

  # THE COMMON NODE VALUE IS A SMALL RECORD, and a level walk pays a fixed cost per level that a
  # depth-first walk does not. So a value is first tried depth-first under a static shape bound: a
  # container at depth 0 may be 16 wide, at depths 1–2 four wide and at depths 3–8 two wide, and
  # nothing deeper may be a container. That admits at most 32593 positions, whatever the value is,
  # cyclic included, so the caps stay under B (and shrink with it if B is ever re-derived lower). A
  # value that fits is `finite` under `walk` too, so the outcome is the walk's and only its cost
  # changes; a value that does not fit, or that holds a function, is decided by `walk`. The tests
  # are inlined rather than routed through `isRecord`: this is the hot path, and the call is measurable.
  scalarNoFunction =
    v: !(builtins.isFunction v || builtins.isList v || builtins.isAttrs v && !(v ? drvPath && isDrv v));
  fitsWithin =
    cap: inner: v:
    if builtins.isAttrs v then
      v ? drvPath && isDrv v
      || (
        let
          cs = builtins.attrValues v;
        in
        builtins.length cs <= cap && builtins.all inner cs
      )
    else if builtins.isList v then
      builtins.length v <= cap && builtins.all inner v
    else
      !(builtins.isFunction v);
  smallAndFinite = builtins.foldl' (inner: cap: fitsWithin cap inner) scalarNoFunction [
    2
    2
    2
    2
    2
    2
    4
    4
    16
  ];

  # "Finite" is SEMI-decidable in pure Nix: a finite value is confirmed in finite time and a
  # non-well-founded one (a self-loop, a two-cycle, an unboundedly generated value) never is. The
  # total form of a semi-decision is a bounded run whose exhaustion returns the SOUND answer, and
  # the sound answer here already exists: the null rule, always-dirty and never false-clean.
  # `finite` is returned only when the walk has run out of positions, so a hash is only ever taken
  # of a value the walk has visited in full.
  classify = v: if smallAndFinite v then "finite" else walk v;

  # The derivation shape, tested at EVERY position rather than at the root. A root-only
  # test fixes the root instance and leaves the class expressible one attribute deeper,
  # which is a repair rather than a construction.
  #
  # `v ? drvPath` is not decoration: the projection below READS `drvPath`, so the
  # predicate that admits a value to that branch must test for it. `type = "derivation"`
  # is the marker convention, and an attrset carrying the marker without the attribute —
  # a stub, a fixture, a redacted or serialised derivation record — is unremarkable.
  # Under a marker-only predicate such a value dies on the missing attribute, and that
  # death is UNCATCHABLE, so the guard would have introduced at admission exactly the
  # failure mode it exists to remove. Under this predicate it falls through to ordinary
  # descent instead.
  isDrv = v: builtins.isAttrs v && (v.type or null) == "derivation" && v ? drvPath;

  # THE SHORT-CIRCUIT IS THE WHOLE MECHANISM. A derivation is self-referential through
  # its own `all`, so a walker that descends into it diverges — and one that recognises
  # it FIRST never descends. Recognising before descending is what removes the class at
  # every depth rather than at the root.
  #
  # ★ THE TAG, RATHER THAN A BARE drvPath STRING, AND THE DIRECTION IS THE POINT. Under
  # a bare-string projection a derivation and a plain string equal to its drvPath project
  # to the identical value, so the plane would hash the two the same and read that swap
  # as UNCHANGED — a FALSE-CLEAN collision, the unsound direction, and the opposite of
  # the null rule's always-dirty. The `__` prefix is the reserved-name convention.
  #
  # ★★ AND NO TAG COULD HAVE CLOSED IT, WHICH IS A THEOREM AND NOT A HEDGE. `project`'s
  # codomain is a subset of its domain — its output is an ordinary Nix value and hence a
  # legal input — so it is idempotent while not being the identity, which means some `x`
  # and `project x` are distinct values with the same image. NO admission-time normalising
  # projection over Nix values can be injective, whatever it projects to. What the tag
  # buys is a NARROWING of the collision class: from any string equal to a drvPath — one
  # ordinary edit away — to an attrset carrying exactly the reserved key with exactly that
  # value. Injectivity is not claimed, not established and not achievable here.
  #
  # ★ WHAT IS NOT REMOVED HERE: the GENERAL non-well-founded class. The projection is
  # lazy and passes a plain self-referential attrset through; the bounded walk above is
  # what meets it. A total acyclicity predicate is still not constructible — deciding it
  # needs the descent that never ends — and the walk does not decide it: it SEMI-decides
  # bounded finiteness, and its bounds fall back to always-dirty rather than refuse. A
  # bound that refuses would be the ceiling invented to bound a cost; one that falls back
  # changes cost only.
  project =
    v:
    if isDrv v then
      { __drvPath = v.drvPath; }
    else if builtins.isList v then
      map project v
    else if builtins.isAttrs v then
      builtins.mapAttrs (_: project) v
    else
      v;
in
{
  inherit
    project
    classify
    maxDepth
    maxPositions
    ;

  # `hashOf` runs over the PROJECTED value. The walk reads the raw one and stops exactly
  # where `project` stops, at a derivation, so it certifies the value `hashOf` is handed.
  # Projection preserves functions (they fall through unchanged), so the discrimination
  # the null rule rests on is untouched: a function beside a derivation still answers
  # `null`. What changes is that the derivation no longer takes the evaluation down first.
  #
  # ★ THE CERTIFICATE IS SCOPED, and the scope is the enumerated exception (ADR-0025 item 1,
  # README Limitations): the walk and a recursive `hashOf` each need up to about D frames,
  # so a CALLER already deeper than `max-call-depth` − D (4990 frames measured at the default,
  # on all three evaluators) still meets the abort this walk removes everywhere else.
  #
  # **`gen-resolve.classKey` RETIRED WITH NO SUCCESSOR CONSTRUCT, and its CEILING did not
  # retire with it.** `classKey` was a stable digest of a consumer-designated attribute's
  # resolved value, offered as a CONSERVATIVE KEY AND EXPLICITLY NOT A SOUNDNESS PROOF: it
  # NARROWS reuse candidates and does not prove two nodes interchangeable. Its stated term
  # on every consumer was that reuse keyed on it MUST be backed by a BYTE-IDENTITY GATE —
  # drvPath equality of the materialized output — as the total correctness oracle. **Key
  # narrows; gate decides.** Inheriting a key without that term makes it a claim it was
  # never written to be.
  #
  # **HALF OF THAT TERM IS VACUOUS HERE, BY THIS PLANE'S OWN DESIGN.** The warning was
  # scoped to a cross-invocation cache, and this plane holds no cross-invocation persistence
  # in any form. There is no such consumer to warn.
  #
  # **THE OTHER HALF IS LIVE AND UNGUARDED, AND IT IS THIS BINDING.** The intra-evaluation
  # reuse decision is keyed on `hashGuarded` and decided by `hashEq`/`hashMoved`, with NO
  # byte-identity gate behind it — the digest is the whole oracle. `project` is
  # non-injective by the theorem stated above, and its residual direction is FALSE-CLEAN,
  # the unsound one. So the retired key's term reads here as: *this plane is the consumer
  # that was told to install a gate, and it has not.* Whether it should is open work
  # (`den-hoag-c5cj` measures one instance of the collision class; the suite's
  # `literalTagStillCollides` pins only its literal-tag sub-class), and this comment records
  # the term rather than discharging it.
  #
  # ANCHOR: R10.1-RIDER-CLASSKEY-CEILING
  hashGuarded =
    hashOf: value:
    let
      projected = project value;
    in
    if smallAndFinite value || walk value == "finite" then hashOf projected else null;

  # Null-safe hash comparison. A null hash means "unhashable / always-dirty"
  # (`hashGuarded`: a function, or a walk past its bounds). Nix `null == null` is TRUE, so a naive
  # `nh != oh` with both null would read as unchanged ⇒ false-clean ⇒ unsound.
  # Route ALL hash comparisons through these so the guard cannot diverge.
  hashEq = nh: oh: nh != null && oh != null && nh == oh;
  hashMoved = nh: oh: nh == null || oh == null || nh != oh;
}
