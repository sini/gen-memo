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
# ★★ THERE IS A SECOND PARTIALITY AND IT IS NOT THE FIRST ONE'S SHAPE, WHICH IS WHY
# IT GETS A DIFFERENT CONSTRUCTION. The null rule is CONSERVATIVE: an unhashable
# function-bearing value is always-dirty, never false-clean, so the plane keeps
# deciding. Cyclicity does not fall back — it ABORTS, and `tryEval` does not contain
# the abort. A value that cannot be hashed is therefore NORMALISED BEFORE ANY WALKER
# REACHES IT rather than met inside the hash: `project` below is a structural
# projection applied at the hash boundary, and `hashGuarded` is its only application
# site, so the ten call sites that hand it a whole node value are covered at one
# place.
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
  containsFunction =
    v:
    if builtins.isFunction v then
      true
    else if builtins.isList v then
      builtins.any containsFunction v
    else if builtins.isAttrs v then
      builtins.any containsFunction (builtins.attrValues v)
    else
      false;

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
  # ★ WHAT IS NOT REMOVED: the GENERAL cyclic class. A plain self-referential attrset
  # aborts this projection exactly as it aborts the walk below, and deliberately so. A
  # total acyclicity predicate is not constructible here: deciding it requires the descent
  # that aborts, and a depth-bounded walk would be a ceiling invented to bound a cost.
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
  inherit project;

  # The walk runs over the PROJECTED value, never the raw one, and so does `hashOf`.
  # Projection preserves functions (they fall through unchanged), so the discrimination
  # the null rule rests on is untouched: a function beside a derivation still answers
  # true. What changes is that the derivation no longer takes the evaluation down first.
  hashGuarded =
    hashOf: value:
    let
      projected = project value;
    in
    if containsFunction projected then null else hashOf projected;

  # Null-safe hash comparison. A null hash means "unhashable / always-dirty"
  # (lib/hash.nix containsFunction). Nix `null == null` is TRUE, so a naive
  # `nh != oh` with both null would read as unchanged ⇒ false-clean ⇒ unsound.
  # Route ALL hash comparisons through these so the guard cannot diverge.
  hashEq = nh: oh: nh != null && oh != null && nh == oh;
  hashMoved = nh: oh: nh == null || oh == null || nh != oh;
}
