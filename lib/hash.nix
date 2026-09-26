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
# ★★ THERE ARE THREE PARTIALITIES, and all three land on that null rule. `hashGuarded` is the
# only application site of the constructions below, so the ten call sites that hand it a whole
# node value are covered at one place.
#   1. FUNCTION-BEARING — the rule above.
#   2. NON-WELL-FOUNDED — a value whose walk does not end. A self-loop, a two-cycle or an
#      unboundedly generated value is an ordinary readable Nix value with no finite walk, and
#      an unbounded walker meets the evaluator's call-depth ceiling on it — an abort `tryEval`
#      does not contain, where the cold evaluation it decides for has a value. A DERIVATION is
#      the ordinary member of the class (a config value containing a package), and `project`
#      below normalises it to a tag before anything descends; EVERYTHING ELSE is met by a
#      BOUNDED walk whose exhaustion lands on null.
#   3. A CATCHABLE BOTTOM IN THE WALK'S PREFIX. A cold read forces only what its consumer
#      reads; the walk forces every position up to the first function, so it is strictly
#      stricter, and a lazy `throw` (or `assert`) no consumer reads fails the walk where the
#      cold read returns. nixpkgs is the ordinary case: its first attribute in name order, its
#      aliases and its meta checks (unfree, broken, insecure) are lazy throws. A walk that
#      throws is caught and lands on null. The catch is around the WALK and never around
#      `hashOf`: the walk forces a superset of what `hashOf` forces, so a throw out of
#      `hashOf` is the caller's own and stays loud.
#
# THE RESIDUE, the enumerated exception (ADR-0025 item 1): a missing attribute, a type error,
# `abort` and a stack overflow in the walk's prefix are UNCATCHABLE by any Nix construction,
# so they still take the evaluation down where a cold read succeeds — unchanged from before
# the catch existed.
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
  # THE ONE BOUND, an engine constant (den-hoag-5ahw). Past it the walk ends `exhausted` and the
  # value is always-dirty, which changes what the plane COSTS and never what it ANSWERS.
  #
  # `maxDepth` (D) is a real ceiling. The walk below spends two evaluator call frames per level
  # (the walker and the `builtins.any` that calls it), so D levels cost 2·D frames against a
  # default `max-call-depth` of 10000; D = 2500 leaves the other half to whatever called the
  # plane. ONE D for upstream Nix, Determinate and Lix. Derivation in the README (Limitations).
  # The budget assumes a `hashOf` that spends one frame per level, as the plane's `toJSON` does;
  # `hashOf` is the caller's, and a deeper-recursing one narrows the caller's half.
  #
  # WHAT THE BOUND COSTS, as properties rather than figures:
  #   - the walker family: at most D closures per `unhashable`, built once per import of this
  #     file and only as deep as a value has reached. Nothing per value.
  #   - R1, a value that exhausts: Θ(D × the acyclic mass the walk completes before each step
  #     down the cycle). A self-loop costs D steps; bulk ahead of the back edge in name order is
  #     re-walked on every unrolling.
  #   - R2, reuse: an acyclic value with a container at image depth ≥ D is always-dirty. The
  #     unbounded walk hashed it only when its caller left room, at caller depth c only below
  #     depth (10000 − c)/2, so the loss is cost and never answer.
  #
  # ★ THE FALLBACK IS SILENT, and that is recorded rather than accepted: nothing tells a
  # consumer its node went always-dirty on the bound. `classify` names the reason and stays
  # internal (tests read it); emitting it is owed through the warned-outcome channel
  # `den-hoag-3yh6` ruled — the result carrying its own provenance — and is not built here.
  maxDepth = 2500;

  # THE DEPTH IS WHICH WALKER RUNS, NOT AN ARGUMENT. `walkerAt k` decides a position at nesting
  # depth k, and its children are decided by the walker one level down, bound once in its closure,
  # so a position costs exactly what the unbounded walk cost it: no counter, no partial
  # application, no comparison. The family is built lazily, once, as deep as a value reaches.
  # Past D the walker is `past`, which answers `true` on any container. Every walker answers
  # `true` on a function and short-circuits, so the walk is a PREFIX of the unbounded depth-first
  # walk in the same order: it forces nothing that walk did not force and stops no later.
  # The builtins are bound locally: a `builtins.X` select inside a walker nested this deep
  # walks a longer environment chain per position than the unbounded walk did.
  walkerFrom =
    onFunction:
    let
      inherit (builtins)
        isFunction
        isList
        isAttrs
        any
        attrValues
        ;
      walkerAt =
        k:
        let
          next = if k + 1 == maxDepth then past else walkerAt (k + 1);
        in
        v:
        if isFunction v then
          onFunction
        else if isList v then
          any next v
        else if isAttrs v then
          any next (attrValues v)
        else
          false;
      past = v: isFunction v && onFunction || isList v || isAttrs v;
    in
    walkerAt 0;
  unhashable = walkerFrom true;
  exhausts = walkerFrom false;
  # `exhausts` walks PAST functions, so it can reach a throw `unhashable` stopped short of. If
  # `unhashable` returned true without throwing and `exhausts` throws, `unhashable` stopped at a
  # function: a bound reached first is reached identically by `exhausts`, which then answers true.
  classify =
    v:
    let
      projected = project v;
      r = builtins.tryEval (unhashable projected);
      e = builtins.tryEval (exhausts projected);
    in
    if !r.success then
      "throws"
    else if !r.value then
      "finite"
    else if e.success && e.value then
      "exhausted"
    else
      "function";

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
  # bounded finiteness, and its bound falls back to always-dirty rather than refuse. A
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
    ;

  # `hashOf` runs over the PROJECTED value, and the walk reads the same image, so it certifies
  # exactly the value `hashOf` is handed, a derivation's `drvPath` content included.
  # Projection preserves functions (they fall through unchanged), so the discrimination
  # the null rule rests on is untouched: a function beside a derivation still answers
  # `null`. What changes is that the derivation no longer takes the evaluation down first.
  #
  # The walk runs under `tryEval`, so a walk that throws is null (the third partiality): the
  # node is always-dirty and recomputed, and its answer is the cold one. That is not the cold
  # COST: the walk still pays to reach its verdict, on top of the recompute, so a node carrying
  # a package set that the throw used to end early now pays for the walk (a node holding
  # `pkgs.perlPackages`: +1.28 M thunks over the import floor, per first hash).
  #
  # ★ THE CERTIFICATE IS SCOPED, and the scope is the enumerated exception (ADR-0025 item 1,
  # README Limitations): the walk needs up to 2·D frames and runs to completion before a
  # one-frame-per-level `hashOf` needs up to D, so a CALLER already deeper than `max-call-depth`
  # − 2·D still meets the abort this walk removes everywhere else — 4990 open caller frames
  # for the self-loop and 4992 for the deepest admitted chain, measured with the suite's
  # `underFrames` at the default on all three evaluators, one frame below the unguarded walk
  # (the `tryEval`). A consumer `hashOf` that spends more per level narrows it.
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
      r = builtins.tryEval (unhashable projected);
    in
    if !r.success || r.value then null else hashOf projected;

  # Null-safe hash comparison. A null hash means "unhashable / always-dirty"
  # (`hashGuarded`: a function, a walk past its bound, or a walk that throws). Nix `null == null` is TRUE, so a naive
  # `nh != oh` with both null would read as unchanged ⇒ false-clean ⇒ unsound.
  # Route ALL hash comparisons through these so the guard cannot diverge.
  hashEq = nh: oh: nh != null && oh != null && nh == oh;
  hashMoved = nh: oh: nh == null || oh == null || nh != oh;
}
