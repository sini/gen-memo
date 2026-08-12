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
# file reading as if its citation had been checked. Every primary cited below WITH A SECTION
# COORDINATE is in the papers archive, and each such coordinate was located in that source rather
# than carried on the retiring library's authority:
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
# ★★ THE EXCLUDED AXIS, NAMED IN THE SAME BREATH, because the sentence above is scoped and a
# scoped sentence read as a universal is how the last one went wrong. Some names cited here are
# held as PRIMARIES and some are not, and "not held as a primary" is NOT the same fact as "absent
# from the archive" — the second is what a filename sweep measures and it is the weaker
# instrument. Measured at CONTENT granularity across `used/` and `reference-catalog/`, with the
# archived names above as live controls and a nonsense token ⇒ 0 as the negative control:
#
#   Kosaraju / Sharir — ⇒ 0 at BOTH granularities. Genuinely absent; nothing here is checkable.
#   Tarjan 1972 — no primary, but NAMED in 3 archived works, one of them Mokhov 2017, itself a
#     primary this ecosystem cites. A recorded acquisition gap.
#   Kleene — no primary, but NAMED in 5 archived works.
#   Magnusson–Hedin — no primary, but the CONSTRUCT IS DESCRIBED IN ARCHIVED PRIMARIES ON EXACTLY
#     THE CITED SUBJECT: Söderberg 2013 names "Magnusson, E., Hedin, G.: Circular reference
#     attributed grammars" in its bibliography and describes their fixed-point iteration in its
#     text, and Hedin 2000 is a co-author primary on reference attribute grammars. This one is
#     therefore CHECKABLE here and is not an absence at all.
#
# **None of these carries a section coordinate**, which is why the scoping above holds and equally
# why it must be stated: they are attributions to a NAMED IDEA. What that means differs per row —
# unverifiable for Kosaraju/Sharir, verifiable at one remove for the other three — and collapsing
# the four into one "absent" list was itself a measurement stated wider than its instrument.
#
# ★★ AND A SECOND EXCLUDED AXIS, ON THE OTHER HALF OF THE SENTENCE. "Located in that source"
# means BY CONTENT, not by heading, and for one primary that distinction is load-bearing: the
# Acar extraction carries NO numbered section headings — its only headings are the title and
# `## Page N` markers (47 of them) — so no §-digit can be confirmed against it. Each was matched
# by the content the coordinate names; none by the digit.
#
# THE RULE IS TOTAL AND IS DELIBERATELY NOT AN ENUMERATION: **every Acar §-number appearing
# anywhere in this repository is content-verified and coordinate-UNVERIFIABLE at the current
# extraction.** An enumerated list stood here and was already wrong — it named §4.3/§4.4/§4.5/§7
# and missed §8 (structural.nix). A hand-maintained list of coordinates drifts from the files it
# describes the moment either moves, which is the same failure as a hand-maintained pin table;
# a total rule cannot go stale and needs no maintenance.
#
# ★★ THREE CLAIMS ARE THIS LIBRARY'S OWN AND ARE ATTRIBUTED TO NO PAPER, in each case because the
# cited section was read and does not contain them: the store's FLATNESS and RELOCATABILITY (not
# in Mokhov §3.1), the REVERSE-TOPOLOGICAL SPLICE (not in the Acar paper), and "EAGER PUSH" (see
# eager.nix — RTD supplies the topological order; the eager characterisation is ours).
#
# ★ THE SPLICE EXCLUSION'S GROUND, RESTATED BECAUSE ONE OF ITS SUPPORTING FIGURES WAS WRONG. The
# exclusion rests on `topolog` ⇒ 0 and `reverse` ⇒ 0 in the Acar extraction, and BOTH still hold —
# the term is not that paper's, and the conclusion is unchanged. What was wrong is a third figure
# carried beside them: `order maintenance` was recorded as ⇒ 0, measured with a SPACE, and the
# paper's surface is HYPHENATED — hyphen-tolerant it is ⇒ 7, including "a standard priority-queue
# algorithm, and an Order-Maintenance [structure]" and "known as the Order-Maintenance Problem".
# ⇒ THE PAPER'S EFFICIENT IMPLEMENTATION IS BUILT ON ORDER MAINTENANCE, and the retired figure
# implied the opposite. A predicate that cannot match the surface it is aimed at returns an
# absence indistinguishable from a finding, and a zero from one is worth nothing. (`virtual clock`
# ⇒ 0 does survive the same hyphen-tolerant re-measurement: `virtual` and `clock` are absent from
# the extraction outright.)
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
    ./warm.nix
  ];

  # The fold REFUSES a collision rather than resolving it by list position — see merge.nix for
  # why, and for the pair that proves the refusal fires.
  inherit (import ./merge.nix args) mergeExports;
in
prelude.foldl' (acc: m: mergeExports (toString m) acc (import m args)) { } modules
