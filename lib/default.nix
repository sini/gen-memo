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
# file reading as if its citation had been checked. Every primary cited below IS in the papers
# archive, and every coordinate was read AT THAT SOURCE rather than carried on the retiring
# library's authority:
#
#   Mokhov 2018 — the scheduler/rebuilder decomposition, and §4.2.2's verifying trace.
#   Reps–Teitelbaum–Demers 1983 — §4.3's AFFECTED set, together with the paper's own statement
#     that AFFECTED "is determined as a result of the updating process itself", which is exactly
#     why the cheap cone is an over-approximation and the exact set is post-filtered from hashes.
#     §5.3's NeedToBeEvaluated and the characteristic graphs are that paper's terms as well.
#   Acar 2002 — the change/propagate split, genuinely the paper's pair of metafunctions.
#   Arntzenius 2016 — Lemma 4, "Fixed points in finite-height pointed posets", whose proof is the
#     iterate-from-⊥ ascent the per-SCC solver performs.
#   Radul 2009 — kick-out! and the support set. Sloane 2010 — circular reference attributes.
#
# ★★ THREE CLAIMS ARE THIS LIBRARY'S OWN AND ARE ATTRIBUTED TO NO PAPER, in each case because the
# cited section was read and does not contain them: the store's FLATNESS and RELOCATABILITY (not
# in Mokhov §3.1), the REVERSE-TOPOLOGICAL SPLICE (not in the Acar paper), and "EAGER PUSH" (see
# eager.nix — RTD supplies the topological order; the eager characterisation is ours).
#
# ★ WHAT STAYS HEDGED is a claim about REACH rather than about provenance: RTD's true
# `O(|AFFECTED|)` optimality and its characteristic graphs are NOT REACHED by this implementation
# in pure evaluation. That hedge is the retiring library's own, it is honest, and it travels.
#
# ★ A PREVIOUS REVISION OF THIS BLOCK SAID RTD AND ACAR WERE "NOT IN THE ARCHIVE". They are, in
# `reference-catalog/` — a different tier from `used/`, and not the same claim. That sentence was
# inherited from a document which scoped its own measurement correctly and then widened it in the
# next clause, and it was repeated here without re-measuring. It is corrected in place rather than
# quietly dropped, because a provenance block carrying an unverified claim is precisely the
# failure this block exists to prevent.
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
