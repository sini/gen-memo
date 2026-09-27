# Rebuilder strategies — three reuse predicates routed through the §3.5 hash gate.
# verify: Mokhov 2018 §4.2 verifying-trace (trace-VALIDITY). earlyCutoff: RTD 1983
# §4.1 unchanged-value cutoff (POST-recompute). needsEval: RTD 1983 §5.3
# NeedToBeEvaluated (PRE-cutoff) — DISTINCT from verify (RTD §5.3 is "complementary
# to / distinct from" the value compare); they COINCIDE only in the single-changed-
# input acyclic data-change envelope, NOT a definitional identity.
#
# Every closed record below is a RECORD door (R5): `prelude.checkRequired` refuses a missing field by
# name, catchably, and admits an extra one. `earlyCutoff` is two doors, one per curried record.
# `assert builtins.isAttrs checked` runs the check at application, where the native formal ran it,
# so a path that reads no field (`needsEval`'s `id == changedId`) still refuses. Every door in this
# library carries it.
{ prelude, ... }:
let
  inherit (import ./hash.nix { }) hashGuarded hashEq hashMoved;
in
{
  verify =
    ctx: args:
    let
      checked = prelude.checkRequired "gen-memo.verify" [ "accessor'" "spliced" ] args;
      inherit (checked) accessor' spliced;
    in
    assert builtins.isAttrs checked;
    id:
    let
      depsMatch = ctx.trace.${id}.deps == accessor'.dependencies id;
      allDepsClean = builtins.all (
        d: hashEq (hashGuarded ctx.hashOf spliced.${d}) (ctx.trace.${d}.hash or null)
      ) (accessor'.dependencies id);
    in
    if depsMatch && allDepsClean then
      {
        reuse = true;
        value = ctx.store.${id};
      }
    else
      {
        reuse = false;
        value = null;
      };

  earlyCutoff =
    args1:
    let
      checked = prelude.checkRequired "gen-memo.earlyCutoff" [ "hashOf" ] args1;
      inherit (checked) hashOf;
    in
    assert builtins.isAttrs checked;
    args2:
    let
      checked = prelude.checkRequired "gen-memo.earlyCutoff" [ "oldHash" "newValue" ] args2;
      inherit (checked) oldHash newValue;
    in
    assert builtins.isAttrs checked;
    hashEq (hashGuarded hashOf newValue) oldHash;

  needsEval =
    args:
    let
      checked = prelude.checkRequired "gen-memo.needsEval" [
        "trace"
        "coneSet"
        "newHashOf"
        "accessor'"
      ] args;
      inherit (checked)
        trace
        coneSet
        newHashOf
        accessor'
        ;
    in
    assert builtins.isAttrs checked;
    changedId: id:
    id == changedId
    || (trace.${id}.hash or null) == null
    || builtins.any (d: (coneSet ? ${d}) && hashMoved (newHashOf d) (trace.${d}.hash or null)) (
      accessor'.dependencies id
    );
}
