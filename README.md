# gen-memo — the incremental plane for the gen ecosystem

[![CI](https://github.com/sini/gen-memo/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-memo/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

gen-memo is the **incremental plane**: a decision layer over the evaluator that never evaluates, only
decides **reuse**. Its definition is a byte-parity oracle against a cold evaluation — a plane output
must be byte-identical to what a cold run produces — so the plane is correct exactly when it is
invisible in the result and visible only in the work avoided.

It answers one question — *given the last evaluation, must key K be recomputed?* — and performs the
minimal recompute plus reuse. In the Mokhov decomposition it is the **rebuilder** dimension alone;
the scheduler is Nix's own laziness, which the evaluator already takes.

**nixpkgs-lib-free.** `lib/` depends on gen-prelude and gen-graph, both pure and nixpkgs-lib-free,
and on no `<nixpkgs>`. A dedicated `purity` suite pins that as a checked property.

## Table of Contents

- [Overview](#overview)
- [The name](#the-name)
- [Gen Ecosystem](#gen-ecosystem)
- [Design Principles](#design-principles)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
- [Edge Convention](#edge-convention)
- [Scope and Soundness](#scope-and-soundness)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)
- [Limitations](#limitations)

## Overview

| Term | Definition |
| --- | --- |
| Store | flat relocatable id-keyed result map `{ <id> = value; }` — plain values, not thunks closed over an evaluation |
| Trace | per-key `{ deps; hash }` verifying record |
| Cone | the dependent cone of `x` — everyone who transitively depends on it |
| Dirty set | changed ids together with their dependent cones (the cheap over-approximation) |
| Affected set | the exact subset whose hash actually moved, discovered by the propagation |
| Splice | `priorStore // fix-of-cone` — recompute the cone, reuse the rest |

The flatness and relocatability of the store are **this library's own design claims about its own
store**, stated in its own voice. They are not attributed to any paper; see
[Theoretical Foundations](#theoretical-foundations).

## The name

The plane is named for its **contract**, not its mechanism. `memo` names the reuse decision — defined
by byte-parity against a cold run — while the mechanisms assigned to it stay free to evolve without
staling the name. "Memoization" is the vocabulary the module system already promises and this plane
discharges.

The runner-up, `gen-delta`, was rejected on the permanent δ homonym in shared spec space. Recorded so
it is not re-proposed.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base |
| [gen-scope](https://github.com/sini/gen-scope) | Demand-driven attribute grammar evaluator — **the sole evaluator**, which this plane decides over and never replaces |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators — supplies the reverse reachability the dependent cone is read from, and the one published SCC partition door |
| [gen-resolve](https://github.com/sini/gen-resolve) | Static attribute schedule and cold fold — consumes this plane's `build`. Its warm half and override cone **have arrived**; the cold fold and the schedule have not, and their destinations are the evaluator and the query-gate home, not here |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure Nix algebra: search monad, records, intensional functions |
| **gen-memo** | **This lib** — the incremental plane (the reuse decision, defined by byte-parity against cold) |

## Design Principles

- **The plane never evaluates.** It decides *whether* to recompute; it never *is* the recompute.
  Evaluation belongs to the evaluator, which is kept thin and sole. The node-eval arrives as a
  caller-supplied `recompute`.
- **The plane does not schedule.** The scheduler is Nix's own laziness; writing one here would
  duplicate the language runtime.
- **The plane reads a cone; it never computes one.** Reverse reachability and the SCC partition are
  gen-graph's, consumed through its published surfaces and never re-implemented here.
- **Byte-parity is the definition, not a test target.** A plane that is fast and not byte-parity is
  not a faster plane; it is a wrong one.
- **A plane that accumulates its own evaluation state has failed.** It observes the evaluator's graph
  and decides against it. It does not become a second place where results live and drift — a "cache"
  that is not defined by the parity oracle is that failure under another name.
- **Loops are iterative and their accumulators are forced.** Nix does not reuse a tail call's frame,
  so a recursive loop's descent depth is its round count and it aborts uncatchably; an unforced
  accumulator field chains a thunk per round and overflows a different stack. Both are constructions
  here, not conventions.

## Quick Start

### As a flake input

```nix
{
  inputs.gen-memo.url = "github:sini/gen-memo";
}
```

Then `gen-memo.lib` is the `genMemo` attrset.

### Standalone (non-flake)

```nix
import (fetchTarball "https://github.com/sini/gen-memo/archive/main.tar.gz") {
  prelude = /* gen-prelude lib */;
  graph = /* gen-graph lib */;
}
```

The standalone entry is a function of the library's dependencies, per the gen root-file convention.

### A first build and override

```nix
let
  ctx = genMemo.build {
    accessor = someGraphAccessor;          # the topology oracle
    recompute = acc: store: id: /* … */;   # the node-eval
    hashOf = v: builtins.hashString "sha256" (builtins.toJSON v);
  };
  after = genMemo.override ctx "someNode" { newData = 1; };
in
after.store                                # the prior store, spliced
```

`examples/dag` is a runnable version of exactly this, including the poisoned-recompute proof that
untouched nodes are never re-evaluated.

### A first warm override

The fold above works over the plane's own store. The warm fold works over an EVALUATION, and the
evaluator is passed in rather than depended on:

```nix
let
  after = genMemo.warmOverride { inherit (genScope) evalWarm; } ctx {
    id = "someHost";
    newDecls = { class = "db"; };
  };
in
after.eval.get "someHost" "resolved"       # re-derived; everything outside the cone is reused
```

`ctx` is a resolved context — roots, the attribute set, the accessor and a prior evaluation. The
plane reads that prior through the evaluator's restricted facade, decides, and hands the decision
back; the evaluator does every recomputation.

## API Reference

27 exports, in six groups.

**Build and reuse decision**

| Export | What it does |
| --- | --- |
| `build` | Full evaluation into a store and a verifying trace. Pre-checks acyclicity and throws a *located*, `tryEval`-catchable blame on a cycle. With a `fixpoint` argument it relaxes the check and solves stratified over the condensation |
| `needsEval` | Whether a node must be recomputed, before any cutoff |
| `earlyCutoff` | Whether a recomputed value's hash moved, after recompute |
| `verify` | Whether a node's trace is still valid — deps unchanged and all dep hashes clean |

Three predicates deciding at three different times; that is the plane's precision story, and they
are not the same predicate under three names.

**Cones**

| Export | What it does |
| --- | --- |
| `affected` / `impactOf` | The dependent cone of one id |
| `dirtySet` | The cheap over-approximation: changed ids together with their cones |
| `affectedSet` | The exact subset whose hash actually moved, post-filtered from the propagation |

**Change and propagate**

| Export | What it does |
| --- | --- |
| `applyDelta` | Data change only: rewrite one node's data, mark it pending, recompute nothing |
| `batch` | Fold `applyDelta` over several deltas |
| `propagate` | Drain the pending set to quiescence over the union cone |
| `override` | The fused convenience — propagate after applyDelta |
| `force` / `forceCtx` | Pull semantics: drain, then read a value (or the quiescent context) |
| `propagateEager` | The cut-heavy fast path: rank-ordered push that recomputes only enqueued nodes |

**Topology change**

| Export | What it does |
| --- | --- |
| `mkAccessor` | Rebuild a full accessor record |
| `retract` | Delete a node and splice it out of its dependents |
| `applyEdgeDelta` | Replace a node's declared edge set, sub-building any newly reachable producers |

**The warm fold — reuse decided for an evaluator**

| Export | What it does |
| --- | --- |
| `warmDecision` | The decision itself: `isClean` (the complement of the dirty cone) and `reusable` (the evaluator's own resolutional vocabulary). Two total functions and no values |
| `warmOverride` | Splice one node's declaration, decide, and hand the evaluator one warm pass |
| `warmResolve` | The batch form: N edits, one union cone, one pass |

**The evaluator is a PARAMETER, not a dependency.** This library declares no evaluator input; the
fold takes `{ evalWarm }` and calls it. So the call reads
`warmOverride { inherit (genScope) evalWarm; } ctx { id, newDecls }`, and what comes back is the
context re-evaluated under the decision — every value in it produced by the evaluator, none by the
plane.

`warmDecision` is exported apart from the fold on purpose. It is the whole of what the plane
contributes, and a surface that offered only the fold would leave the interface the design rests on
unobservable.

**Cycles and provenance**

| Export | What it does |
| --- | --- |
| `runScc` | Solve one strongly connected component to its least fixed point |
| `restabilize` | The cyclic-capable analogue of `override` |
| `support` / `supportDirect` | The transitive (or immediate) declared producers of a node |
| `why` | The verdict an override would produce for a node: recomputed, cutoff or unaffected |
| `whyNot` | The same as a total record — `{ reason; at }` for every verdict |

The internal hash guards (`hashGuarded`, `hashEq`, `hashMoved`) are **not** on this surface. They are
imported directly by the files that need them; the evaluator this plane decides for is owed no hash
surface at all.

## Edge Convention

`accessor.edges id` is **the ids that `id` depends on** — consumer to producer. A dependent cone is
therefore reverse reachability over those edges.

## Scope and Soundness

- **`override` is a DATA-change operation.** It replaces one node's data; edges are fixed. Its
  soundness claim is "data-change override equals a full rebuild", not unconditional soundness.
  Topology changes go through `retract` / `applyEdgeDelta`, which rebuild the accessor and re-run a
  located cycle check.
- **`warmOverride` is a data-change operation too, and refuses the other kind BY NAME.** It decides
  reuse from a cone read over the topology as it stands, so an edit carrying an edge key throws
  rather than being served a decision computed against a shape that no longer holds.
- **The warm fold's soundness rests on the caller's declared edge relation OVER-DECLARING cross-node
  reads.** A consumer that reads another node's attribute without declaring the edge sits outside
  the cone, is judged clean, and is served its stale prior. That is not a defect in the cone; it is
  what an under-declared relation means, and `ci/tests/warm-override-cross-node.nix` witnesses both
  branches rather than only the agreeable one.
- **Store equality is over hashable values.** A node whose value carries a function is sound by
  being always-dirty, not by comparing equal.
- **The cyclic path is outside the acyclic envelope.** Per-SCC convergence rests on the consumer's
  unchecked monotonicity and finite-height obligations; the only runtime divergence guard is the
  consumer-declared per-member `maxIter`, which refuses with a catchable located blame.
- **`maxIter` is required of every cyclic member and has no default.** The bound is honest only as
  the consumer's own assertion about their own lattice; supplying one here would have the engine
  assert a bound about a lattice it cannot inspect — neither monotonicity nor height is checkable —
  and then blame the consumer at a number the consumer never wrote. A member with no `maxIter` is a
  build error naming the members that owe one, not a silent fallback.

## Testing

```bash
nix flake check ./ci                     # what CI runs
nix-unit --flake ./ci#tests              # run everything
nix-unit --flake ./ci#tests.byte-parity  # a single suite
```

18 suites. Beyond the migrated content's own, two are the plane's oracles:

- **`byte-parity`** — the definition, armed: the same input evaluated twice, once with the decision
  forced to nothing-is-clean, compared on `drvPath` where the output is a derivation and on the value
  otherwise. It carries its own live control, because a comparator that reported parity for
  everything would pass every other cell in the file.
- **`fleet`** — the measurement lab's Arm R: a shared producer with dependent hosts, a localized
  single-host edit, the byte gate plus the poisoned-recompute proof, and the `>= 0.60` saving floor.
  Which half of that floor migrated and which did not is stated in the suite itself.

`nix-unit` collects only cells named `test-*`; a cell that loses the prefix disappears from the
nix-unit run, which still reports green. `nix flake check` — what CI runs — backstops this: gen's
asserter does not filter on the prefix. `AGENTS.md` carries both armings and the both-ways
reconciliation command.

## Theoretical Foundations

**★ CITATION PROVENANCE.** Every primary this library cites **with a section coordinate** is in the
papers archive, and each such coordinate was located in that source rather than carried on the
retiring library's authority.

**The excluded axis, named in the same breath**, because a scoped sentence read as a universal is how
the previous revision of this section went wrong. Some cited names are held as **primaries** and some
are not — and *not held as a primary* is **not the same fact** as *absent from the archive*. The
second is what a filename sweep measures, and it is the weaker instrument. At **content** granularity
across `used/` and `reference-catalog/`, with archived names as live controls and a nonsense token
⇒ 0 as the negative control:

| cited name | primary? | discussed in archived work |
|---|---|---|
| Kosaraju / Sharir | no | **⇒ 0 at both granularities** — genuinely absent, nothing checkable |
| Tarjan 1972 | no | named in **3** archived works, one of them Mokhov 2017 — itself a primary this ecosystem cites. A recorded acquisition gap |
| Kleene | no | named in **5** archived works |
| Magnusson–Hedin | no | **the construct is described in archived primaries on exactly the cited subject** — Söderberg 2013 lists "Magnusson, E., Hedin, G.: Circular reference attributed grammars" and describes their fixed-point iteration; Hedin 2000 is a co-author primary on reference attribute grammars. Checkable here; not an absence |

None of these carries a section coordinate, which is why the scoping holds and why it has to be said:
they are attributions to a *named idea*. What that means differs per row — unverifiable for
Kosaraju/Sharir, verifiable at one remove for the other three — and collapsing them into one "absent"
list was itself a measurement stated wider than its instrument.

**And "located in that source" means BY CONTENT, not by heading.** The Acar extraction carries no
numbered section headings at all — its only headings are the title and 47 `## Page N` markers — so no
§-digit can be confirmed against it. The rule is **total, and deliberately not an enumeration**: every
Acar §-number anywhere in this repository is content-verified and **coordinate-unverifiable** at the
current extraction. An enumerated list stood here and was already wrong, naming §4.3/§4.4/§4.5/§7 and
missing §8; a hand-maintained list of coordinates drifts from the files it describes the moment either
moves, and a total rule cannot go stale.

Three claims are the library's own and are attributed to no paper, in each case because the cited
section was read and does not contain them: the store's **flatness and relocatability** (not in
Mokhov §3.1), the **reverse-topological splice** (not in the Acar paper), and **"eager push"** (RTD
supplies the topological order; the eager characterisation is this library's).

★ **The splice exclusion's ground, restated because one supporting figure was wrong.** It rests on
`topolog` ⇒ 0 and `reverse` ⇒ 0, and both still hold, so the conclusion is unchanged. A third figure
carried beside them was not: `order maintenance` ⇒ 0 was measured with a **space** against a
**hyphenated** surface — hyphen-tolerant it is ⇒ **7**, and the paper's efficient implementation is
*built on* an order-maintenance structure. A predicate that cannot match the surface it is aimed at
returns an absence indistinguishable from a finding.

What stays hedged is a claim about *reach*, not provenance: RTD's true `O(|AFFECTED|)` optimality
and its characteristic graphs are **not reached** by this implementation in pure evaluation.

★ An earlier revision of this section said RTD 1983 and Acar 2002 were "not in the archive". They
are, in `reference-catalog/` — a different tier from `used/`, and not the same claim. The sentence
was inherited from a document that scoped its own measurement correctly and widened it in the next
clause, and repeated here without re-measuring.

- **Mokhov, Mitchell & Peyton Jones (2018), *[Build Systems à la Carte](https://www.microsoft.com/en-us/research/publication/build-systems-la-carte/)*.**
  The scheduler/rebuilder decomposition. gen-memo is the **rebuilder** dimension; the scheduler is
  Nix's own laziness, taken by the evaluator. In the paper's Table 2 the claimed cell is
  **suspending** (§4.1.3) × **verifying traces** (§4.2.2) — deliberately not the paper's own Nix row,
  `nix = suspending dctRebuilder`, which is deep constructive traces (§4.2.4) and does not support
  the early cutoff the invalidation claim needs.

  **The memory claim is NARROWED, and the narrowing is written here rather than inferred from what
  got built.** §4.2.2's *cross-build* memory is **not** what this plane has: a Mokhov rebuilder
  consults build information that "persists from one invocation of the build system to the next"
  (§3.1), and a pure Nix evaluation has no cross-invocation persistence. **The plane's memory is the
  prior evaluation's own accessor, live inside the same evaluation**, and its scope is
  intra-evaluation reuse — the override cone, and reuse across the many targets composed within one
  evaluation. What survives is the verifying-trace *shape*, the rebuilder/scheduler decomposition,
  and the reuse decision itself. What does not is persistence across invocations, in any form.

  **The store's flatness and relocatability are NOT Mokhov's.** §3.1 defines the Store and states
  neither property. They are this library's own claim about its own store, and are made in its own
  voice everywhere they appear.

- **Reps, Teitelbaum & Demers (1983).** Reverse-transitive-dependency propagation supplies the
  invalidation relation: the AFFECTED set (§4.3) and the unchanged-value cutoff (§4.1). True
  `O(|AFFECTED|)` optimality and characteristic graphs are recorded as **not reached** in pure
  evaluation — a finding about this implementation's reach that travelled with the content. The
  attributions themselves are verified at the primary, including the paper's own point that
  AFFECTED "is determined as a result of the updating process itself" — the reason the cheap cone
  is an over-approximation and the exact set is post-filtered from hashes.

- **Acar (2002).** The change/propagate split is the paper's: `applyDelta` and `propagate` are its
  two metafunctions, de-conflated here rather than fused — verified at the primary. The
  *reverse-topological splice* is not there at all, so that mechanism is this library's own and is
  attributed to no one.

- **Arntzenius (2016), Datafun.** Reverse reachability, and the per-SCC least fixed point by
  iterate-from-bottom on finite-height semilattices.

- **Fleischer, Hendrickson & Pınar (2000)** by way of gen-graph, whose partition door supplies the
  SCC quotient this library reads and does not compute.

**The definition, not a citation.** The plane's correctness condition is the **byte-parity oracle**:
a plane output must be byte-identical to a cold evaluation.

## Limitations

- **The store's admissible values are function-free AND ACYCLIC.** The null-hash rule records the
  first partiality — Nix's hash is partial on function-bearing values, so those get `hash = null` and
  are conservatively always-dirty. That rule has **no paper behind it**; it is an operational Nix
  fact. The second partiality is not conservative: the guard's structural walk has no cycle guard, so
  a **self-referential value aborts with a stack overflow that `tryEval` does not catch**. A Nix
  derivation is self-referential (`drv.all`'s first element is the derivation itself), so a raw
  derivation cannot be a node value today. `ci/tests/byte-parity.nix` records the measurement and
  carries each node's `drvPath` instead.
- **No cross-invocation persistence**, by design and by the narrowing above.
- **`batch` layers its accessor overrides**, so N deltas leave an N-deep `nodeData` closure chain
  paid on every later read. Forcing the accumulator does not flatten it; only re-expressing the
  override as one data map would, and that is a change to what `applyDelta` means.
