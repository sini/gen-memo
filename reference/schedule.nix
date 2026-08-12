# THE SCHEDULER — the caller's side of the seam, deliberately NOT part of the plane.
#
# Mokhov 2018 decomposes a build system into a SCHEDULER, which decides the order tasks run in
# and produces the resulting store, and a REBUILDER, which decides whether a task must run at
# all. gen-memo is the rebuilder half and only that half: it produces a decision, and something
# else applies it. In this ecosystem the scheduler is Nix's own laziness, which the evaluator
# already takes — so the plane needs no scheduler of its own, and what it needs instead is for
# whoever calls it to bring one.
#
# WHY THIS FILE IS NOT UNDER `lib/`. A construct EVALUATES when it binds a self-referential store
# over the node set and passes it into the caller's node computation, letting one node's
# computation observe another's output. That is precisely what the expression below does, and a
# plane holding it would be a plane that accumulates its own evaluation state — the failure the
# decision interface exists to make inexpressible. `lib/` does not import this file and
# `lib/default.nix` does not fold it in; it reaches the plane only by being handed in, the same
# way `evalWarm` is handed to the warm fold.
#
# WHY IT SHIPS AT ALL, rather than each caller writing five lines. A caller that HAS an evaluator
# hands that instead, and that is the intended direction. But a caller with none — a test, an
# example, a corpus fixture — still needs a scheduler, and the same five lines written by five
# callers is five chances to get the merged view or the reuse arm subtly wrong, in a way whose
# only symptom is a byte-parity failure somewhere else. One reference implementation, read by the
# suite that pins the parity, is the honest form of that.
{ prelude }:
{
  # schedule :: {
  #   accessor,    # topology oracle, handed straight back to `recompute`
  #   domain,      # [NodeId] — the ids this pass produces
  #   base,        # Store — values outside the domain, and the source a reused node is served from
  #   recompute,   # accessor -> Store -> NodeId -> Value — the caller's node computation
  #   isClean,     # NodeId -> Bool — THE PLANE'S DECISION, applied here and computed nowhere near here
  # } -> { <id> = value }   # domain-keyed
  #
  # The knot is `prelude.fix`: dependency-order resolution is call-by-need, so a node reading a
  # peer through `view` gets that peer's value without anyone computing an order. It terminates
  # because the plane prechecks acyclicity before handing a domain over — the precheck is the
  # rebuilder's, the termination it buys is the scheduler's.
  #
  # `isClean` is applied and never inspected. A clean node's value is served from `base`, which is
  # the prior store, and `recompute` is not called for it at all — reuse is the absence of the
  # call, not a cheaper call.
  schedule =
    {
      accessor,
      domain,
      base,
      recompute,
      isClean,
    }:
    prelude.fix (
      s:
      let
        view = base // s;
      in
      prelude.genAttrs domain (id: if isClean id then base.${id} else recompute accessor view id)
    );
}
