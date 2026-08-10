# gen-memo — the incremental plane for the gen ecosystem

[![CI](https://github.com/sini/gen-memo/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-memo/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

gen-memo is the **incremental plane**: a decision layer over the evaluator that never evaluates, only
decides **reuse**. Its definition is a byte-parity oracle against a cold evaluation — a plane output
must be byte-identical to what a cold run produces — so the plane is correct exactly when it is
invisible in the result and visible only in the work avoided.

> **This repository is a scaffold. The library exports nothing yet.**
> `lib/default.nix` is `{ }`. The plane's content is named but unwritten, because the interface it
> needs — what the evaluator exposes to the plane — is still an open design item. The shell exists so
> the ruled moves that were gated on it have somewhere to land. See
> [Status](#status-what-is-here-and-what-is-not).

## Table of Contents

- [Status](#status-what-is-here-and-what-is-not)
- [The name](#the-name)
- [Gen Ecosystem](#gen-ecosystem)
- [Design Principles](#design-principles)
- [Quick Start](#quick-start)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Status — what is here, and what is not

**Here:** the repository shell — flake, standalone entry, CI wired to the shared gen runner, the
purity invariant, and a surface tripwire that fails the moment an export appears without the
documentation to match.

**Not here, and deliberately:**

- **Any plane or engine content.** The scope↔plane interface — what the evaluator exposes (node
  hashes, edge sets, traces) — is a named, unsettled design item. An export written ahead of it
  would fix that interface by accident.
- **Hub roster membership and a stratum.** `gen/lib/mkGenLibs.nix`'s stratum declaration is total
  and explicit by design: a member with no entry there is a build error, never a member of an
  implicit residue bucket. Assigning gen-memo a stratum is therefore a design decision, not
  scaffolding. The buckets are five — `substrate`, `modules`, `aspects`, `framework`, `retiring` —
  and the plane is none of the middle three, nor `retiring`, which names a member leaving the roster
  where the plane is the destination of three of those five retirements. The elimination therefore
  still lands on "substrate by default", exactly the silent choice that declaration exists to
  forbid, so the stratum needs a ruling and does not get one here. gen-vars and gen-rebuild sit off
  the roster on the same footing.
- **Migrated content.** The warm fold and override cone (today in
  [gen-resolve](https://github.com/sini/gen-resolve)), the dirty-cone propagation (today in
  [gen-rebuild](https://github.com/sini/gen-rebuild)), and gen-flake's compose warm/override/trace
  arm are all destined here and none have moved. Each is its own sequenced piece of work.

## The name

The plane is named for its **contract**, not its mechanism. `memo` names the reuse decision — defined
by byte-parity against a cold run — while the mechanisms assigned to it (the warm fold and override
cone, the dirty-cone propagation) stay free to evolve without staling the name. "Memoization" is the
vocabulary the module system already promises and this plane discharges.

The runner-up, `gen-delta`, was rejected on the permanent δ homonym in shared spec space. Recorded so
it is not re-proposed.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base |
| [gen-scope](https://github.com/sini/gen-scope) | Demand-driven attribute grammar evaluator — **the sole evaluator**, which this plane decides over and never replaces |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators — supplies the reverse reachability the dependent cone is read from |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | The rebuilder core as it exists today: result store, verifying trace, dirty propagation — **this plane's content, not yet moved** |
| [gen-resolve](https://github.com/sini/gen-resolve) | Static attribute schedule + cold/warm fold — its **warm** half and override cone are destined here; the schedule and cold path are not |
| [gen-flake](https://github.com/sini/gen-flake) | The composition boundary — its compose warm/override/trace arm is destined here |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure Nix algebra: search monad, records, intensional functions |
| **gen-memo** | **This lib** — the incremental plane (the reuse decision, defined by byte-parity against cold) |

## Design Principles

- **The plane never evaluates.** It decides *whether* to recompute; it never *is* the recompute.
  Evaluation belongs to the evaluator, which is kept thin and sole.
- **The plane does not schedule.** In the Mokhov decomposition this is the **rebuilder** dimension
  alone. The scheduler is Nix's own laziness, which the evaluator already takes — writing one here
  would duplicate the language runtime.
- **Byte-parity is the definition, not a test target.** A plane that is fast and not byte-parity is
  not a faster plane; it is a wrong one.
- **A plane that accumulates its own evaluation state has failed.** It observes the evaluator's graph
  and decides against it. It does not become a second place where results live and drift — a "cache"
  that is not defined by the parity oracle is that failure under another name.
- **Reads are derived from the graph, never declared.** Hand-declared read surfaces across this stack
  were measured dead or under-scoped; the plane does not add another.
- **nixpkgs-lib-free.** `lib/` depends on no `nixpkgs.lib`; nixpkgs enters only in `ci/`, as the test
  harness and formatter. `ci/tests/purity.nix` pins this as a checked property.

## Quick Start

### As a flake input

```nix
{
  inputs.gen-memo.url = "github:sini/gen-memo";
  # gen-memo declares no inputs — a consumer's lock gains no transitive dependency.
}
```

Then `gen-memo.lib` is the `genMemo` attrset. It is `{ }` at this revision.

### Standalone (non-flake)

```nix
let genMemo = import (fetchTarball "https://github.com/sini/gen-memo/archive/main.tar.gz");
in genMemo
```

The standalone entry is the lib **value**, not a function, because gen-memo declares no inputs — the
same shape gen-prelude and gen-algebra ship. It becomes a function of its dependencies when it
acquires any.

## Testing

Two suites under `ci/`: `purity` (the nixpkgs-lib-free invariant over `lib/**.nix` + `flake.nix` +
`default.nix`, carrying its own positive control so the absence claim cannot pass by a dead
predicate) and `surface` (the empty-export tripwire, plus the standalone-entry/lib agreement).

```bash
nix flake check ./ci                     # what CI runs
nix-unit --flake ./ci#tests              # run everything
nix-unit --flake ./ci#tests.purity       # a single suite
```

The surface suite is a **tripwire, not a wall**: when the first export lands it fails, and the author
updates it alongside `AGENTS.md` and the canonical reference spec in the same change. That is the
point — the library cannot widen silently.

`nix-unit` collects only cells named `test-*`; a cell that loses the prefix disappears from the
nix-unit run, which still reports green. `nix flake check` — what CI runs — backstops this: gen's
asserter does not filter on the prefix, so it still catches a broken un-prefixed cell (exit 1).
`AGENTS.md` carries both armings and the both-ways reconciliation command.

## Theoretical Foundations

**Claimed, unrealized.** No code in this repository realizes either claim — so the relationship is
neither *Implements*, which would be false on its face for an empty library, nor *Informed by*,
which understates what the first content is answerable to. They are recorded because a claim stated
up front cannot be quietly swapped for a weaker one later. § Academic Provenance in the canonical
reference spec — `papers/den-architecture/gen-specs/gen-memo/REFERENCE.md`, which lives in the
papers repo rather than here — is the canonical statement; this list restates it and adds nothing.

- **Mokhov, Mitchell & Peyton Jones (2018), *[Build Systems à la Carte](https://www.microsoft.com/en-us/research/publication/build-systems-la-carte/)*.**
  The scheduler/rebuilder decomposition. gen-memo is the **rebuilder** dimension; the scheduler is
  Nix's own laziness, taken by the evaluator. In the paper's Table 2 the claimed cell is
  **suspending** (§4.1.3) × **verifying traces** (§4.2.2) — deliberately not the paper's own Nix row,
  `nix = suspending dctRebuilder`, which is deep constructive traces (§4.2.4) and does not support
  the early cutoff the invalidation claim below needs. gen-rebuild realizes a verifying trace today,
  and that is the content destined to move here. **Open precondition:** a Mokhov rebuilder consults
  build information that "persists from one invocation of the build system to the next" (§3.1), and
  a pure Nix evaluation has no cross-invocation persistence — how the plane carries that is spec
  work, not implementation detail.
- **Reps, Teitelbaum & Demers (1983).** Reverse-transitive-dependency propagation supplies the
  invalidation relation: the AFFECTED set (§4.3) and the unchanged-value cutoff (§4.1). True
  `O(|AFFECTED|)` optimality and characteristic graphs are recorded as **not reached** in pure
  evaluation — a finding that travels with the content rather than being re-opened by the move.
