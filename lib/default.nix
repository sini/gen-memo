# gen-memo — the INCREMENTAL PLANE.
#
# A decision layer over the evaluator. It never evaluates; it decides REUSE. Its definition is a
# byte-parity oracle against a cold evaluation — a plane output must be byte-identical to what a
# cold run produces — so the plane is correct exactly when it is invisible in the result and
# visible only in the work avoided.
#
# Theory: Mokhov, Mitchell & Peyton Jones (2018), "Build Systems à la Carte" — the
# scheduler/rebuilder decomposition, of which this plane is the REBUILDER half alone. The scheduler
# is Nix's own laziness, which the evaluator already takes, so no scheduling belongs here.
# Invalidation is reverse-transitive-dependency propagation over the graph the evaluator exposes.
#
# THE PLANE'S MEMORY IS THE SAME EVALUATION'S OWN ACCESSOR. Mokhov's rebuilder is defined by
# consulting build information that persists from one invocation of the build system to the next,
# and §4.2.2 calls the verifying trace exactly that memory. A pure Nix evaluation has no
# cross-invocation persistence and this plane claims none: what it reuses is a prior result held
# live inside the SAME evaluation — the override cone, and reuse across the many targets composed
# within one evaluation. The verifying-trace shape, the rebuilder/scheduler decomposition and the
# reuse decision itself are Mokhov's and are carried; persistence across invocations is not, in any
# form, and no file below may re-assert it.
#
# ★ CITATION PROVENANCE, stated here once for every file below, because the alternative is each
# file reading as if its citation had been checked. Mokhov 2018 is in the archive and the claims
# made against it here were read at that source. Reps–Teitelbaum–Demers 1983 and Acar 2002 ARE
# NOT IN THE ARCHIVE: every RTD and Acar attribution below is REPORTED FROM THE RETIRED LIBRARY'S
# OWN DOCUMENTATION rather than verified against the primary, and each travels with the hedge its
# author attached — RTD's true `O(|AFFECTED|)` optimality and its characteristic graphs are stated
# there as NOT REACHED in pure evaluation, and the reverse-topological splice is that library's own
# mechanism rather than anything the Acar paper is known to state. Nothing here stands in for
# reading the primary, and a later revision that acquires either paper re-derives these lines
# instead of deleting this one.
#
# ★ THE STORE'S FLATNESS AND RELOCATABILITY ARE THIS LIBRARY'S OWN DESIGN CLAIM ABOUT ITS OWN
# STORE, in its own voice. They were previously attributed to Mokhov 2018 §3.1 and that section
# contains neither property; the property is real and the attribution was not.
{
  prelude,
  graph,
}:
let
  args = { inherit prelude graph; };

  # Per-concern modules; one file = one concern.
  #
  # `hash.nix` is deliberately ABSENT from this list. Its guards are internal to the plane and are
  # imported directly by the files that need them, which is the state that shipped; adding them to
  # the surface here would widen the library on the way through a migration, and the evaluator this
  # plane decides for is owed no hash surface at all.
  modules = [
    ./build.nix
    ./affected.nix
    ./dirtySet.nix
    ./strategies.nix
    ./affectedSet.nix
    ./provenance.nix
    ./drivers.nix
    ./eager.nix
    ./structural.nix
    ./restabilize.nix
  ];

  # The fold REFUSES a collision rather than resolving it by list position — see merge.nix for
  # why, and for the pair that proves the refusal fires.
  inherit (import ./merge.nix args) mergeExports;
in
prelude.foldl' (acc: m: mergeExports (toString m) acc (import m args)) { } modules
