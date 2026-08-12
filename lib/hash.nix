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
# NOT PART OF THE PUBLIC SURFACE, deliberately. `lib/default.nix` does not fold this
# file in; the files that need the guards import it directly. That is the state this
# content shipped in and it is kept rather than widened in passing: the plane hashes
# for its own reuse decision, and the evaluator it decides for is owed no hash surface
# at all. Putting these three on the export list would be a new surface arriving under
# cover of a move.
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
in
{
  hashGuarded = hashOf: value: if containsFunction value then null else hashOf value;

  # Null-safe hash comparison. A null hash means "unhashable / always-dirty"
  # (lib/hash.nix containsFunction). Nix `null == null` is TRUE, so a naive
  # `nh != oh` with both null would read as unchanged ⇒ false-clean ⇒ unsound.
  # Route ALL hash comparisons through these so the guard cannot diverge.
  hashEq = nh: oh: nh != null && oh != null && nh == oh;
  hashMoved = nh: oh: nh == null || oh == null || nh != oh;
}
