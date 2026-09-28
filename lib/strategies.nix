# Rebuilder strategies — three reuse predicates routed through the §3.5 hash gate.
# verify: Mokhov 2018 §4.2 verifying-trace (trace-VALIDITY). earlyCutoff: RTD 1983
# §4.1 unchanged-value cutoff (POST-recompute). needsEval: RTD 1983 §5.3
# NeedToBeEvaluated (PRE-cutoff) — DISTINCT from verify (RTD §5.3 is "complementary
# to / distinct from" the value compare); they COINCIDE only in the single-changed-
# input acyclic data-change envelope, NOT a definitional identity.
#
# The argument grammar (den-hoag-7gp66 P2, R7): operands are positional, configuration first and the
# subject last, so `verify ctx accessor' spliced id` and `earlyCutoff hashOf oldHash newValue` carry
# no field check — positional arity is structural. `needsEval`'s four operands stay ONE record
# (R7 (a)): a trace, a cone set, a hash function and an accessor are four sorts with no order among
# them, so any positional order would be an arbitrary one to remember. The record is a
# `prelude.door` (open, R5): a missing field is refused by name, catchably, when the record is
# applied — before `changedId`/`id`, so a path that reads no field still refuses — and an extra one
# is admitted. `cores.needsEval` is its unchecked core, which this library's own callers use
# (a check never sits on an internal path over a loop-invariant record); `default.nix` strips
# `cores` from the surface.
{ prelude, ... }:
let
  inherit (import ./hash.nix { }) hashGuarded hashEq hashMoved;

  needsEvalCore =
    args:
    let
      inherit (args)
        trace
        coneSet
        newHashOf
        accessor'
        ;
    in
    changedId: id:
    id == changedId
    || (trace.${id}.hash or null) == null
    || builtins.any (d: (coneSet ? ${d}) && hashMoved (newHashOf d) (trace.${d}.hash or null)) (
      accessor'.dependencies id
    );
in
{
  cores.needsEval = needsEvalCore;

  verify =
    ctx: accessor': spliced: id:
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

  # The hash function is configuration, the prior hash the reference, and the new value the subject.
  earlyCutoff =
    hashOf: oldHash: newValue:
    hashEq (hashGuarded hashOf newValue) oldHash;

  needsEval = prelude.door {
    name = "gen-memo.needsEval";
    required = [
      "trace"
      "coneSet"
      "newHashOf"
      "accessor'"
    ];
    open = true;
  } needsEvalCore;
}
