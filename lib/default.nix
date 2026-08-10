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
# THE SURFACE IS EMPTY, AND DELIBERATELY SO. The plane's name states its CONTRACT — the reuse
# decision — and deliberately not its mechanism, so the mechanisms stay free to change without
# staling the name. No export may be written ahead of the spec that settles what the plane reads
# from the evaluator, because an export written first would fix that interface by accident; and a
# plane that accumulates its own evaluation state has, by construction, already failed. What lands
# here is the warm fold and override cone, and the dirty-cone propagation, once that interface is
# named. `ci/tests/surface.nix` holds this file to the empty surface, so the first export arrives
# as a failing test rather than as a silent widening.
{ }
