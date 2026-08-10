# gen-memo — Canonical Reference

**Source of truth:** [github:sini/gen-memo](https://github.com/sini/gen-memo)
**Status:** SCAFFOLD — repository shell, empty export surface
**Last audited:** 2026-08-10

## Purpose

gen-memo is the **incremental plane**: a decision layer over the evaluator that never evaluates, only
decides **reuse**. Its definition is a byte-parity oracle against a cold evaluation — a plane output
must be byte-identical to what a cold run produces. The plane is therefore correct exactly when it is
invisible in the result and visible only in the work avoided.

In the Mokhov decomposition it is the **rebuilder** dimension alone. The scheduler is Nix's own
laziness, which the evaluator already takes; the plane adds no scheduling.

The name states the plane's **contract** — the reuse decision — rather than its mechanism, so the
mechanisms assigned to it stay free to evolve without staling the name.

### Non-goals

- **No evaluation.** The plane decides *whether* to recompute; it never *is* the recompute. A
  caller-supplied `recompute` is the shape this takes.
- **No scheduling.** The scheduler half of the decomposition is the language runtime's, not a gen
  library's.
- **No accumulated evaluation state.** A plane that becomes a second place where evaluation results
  live and drift has failed by construction. A "cache" not defined by the parity oracle is that
  failure under another name.
- **No declared reads.** Reads are derived from the graph. Hand-declared read surfaces across this
  stack were measured dead or under-scoped; the plane does not add another.
- **No well-definedness or stratification checking.** Those survive as graph-native analysis queries
  over the graph the engine exposes — not as a plane concern, and not as a standalone analysis
  library.
- **No graph algorithms.** The dependent cone is *read*; the reverse reachability that computes it
  belongs to gen-graph and is never re-implemented here.

## Current state

**The library exports nothing.** `lib/default.nix` is `{ }`; `import ./lib`, `import ./.` and
`inputs.gen-memo.lib` are all `{ }`.

This is a deliberate state, not an unfinished one. The interface the plane needs — what the evaluator
exposes to it (node hashes, edge sets, traces) — is a named, unsettled design item, and an export
written ahead of it would fix that interface by accident.

`ci/tests/surface.nix` asserts the empty surface, so the first export lands as a failing test and
obliges its author to state the new surface here and in `AGENTS.md` in the same change.

## Destined content — where it lives today

None of the following has moved. Each is separately sequenced work, and this table exists so the
content is findable and so nothing is re-derived from scratch when it moves.

| Content | Lives today in | Note |
|---|---|---|
| Result store, verifying trace, dirty-cone propagation | `gen-rebuild` (`lib/build.nix`, `lib/hash.nix`) | The plane's core. gen-rebuild's library shell retires with the move |
| Warm fold and override cone | `gen-resolve` (`lib/override.nix`, the warm half of `lib/resolve.nix`) | Only the **warm** half is destined here — the static attribute schedule and the cold path stay with gen-resolve's disposition |
| Compose warm / override / trace | `gen-flake` | Explicitly gated on this repository existing; gen-flake dissolves and its repo orphans as reference |
| Failure-attribution inputs | `gen-flake` `diff.nix` (stays in the orphaned repo) | Its two hedges — function-equality blindness in `dropFns`, and the four-reserved-names group misclassification — are named inputs to the plane's failure-attribution **spec**, not code to copy |

Adjacent but **not** destined here: gen-demand's demand/kind folds re-express over the evaluator, a
different destination in the same retirement.

## Academic Provenance

No code in this repository realizes these claims yet. They are recorded because the first content is
answerable to them, and a claim stated up front cannot be quietly swapped for a weaker one later.

| Feature | Source | Relationship |
|---|---|---|
| Scheduler/rebuilder decomposition; the plane is the rebuilder dimension | Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte* | **Claims to implement.** The flat relocatable store (§3.1), verifying trace (§4.2.2) and `verify` (§4.2) are realized today in gen-rebuild — the content destined to move here |
| Invalidation relation: the AFFECTED set and the unchanged-value cutoff | Reps, Teitelbaum & Demers (1983) | **Informed by.** Reverse-transitive-dependency propagation. True `O(\|AFFECTED\|)` optimality and characteristic graphs are recorded as **not reached** in pure evaluation; that finding travels with the content rather than being re-opened by the move |
| The change/propagate split and the reverse-topo splice | Acar et al. (2002), *Adaptive Functional Programming* | **Informed by**, inherited with gen-rebuild's content |

**Byte-parity is a definition, not a citation.** A plane output must be byte-identical to a cold
evaluation. A plane that is fast and not byte-parity is not a faster plane; it is a wrong one.

## Layering & Entry Points

gen-memo declares **no flake inputs**. A consumer's lock gains no transitive dependency by taking it.

| Entry | Form | Value at this revision |
|---|---|---|
| `inputs.gen-memo.lib` | flake output — `import ./lib` | `{ }` |
| `import ./.` | root `default.nix` — the lib **value**, not a function | `{ }` |
| `import ./lib` | the library itself | `{ }` |

The root entry is a value rather than a function because there are no dependencies to default. When
the plane acquires them, `default.nix` becomes a function whose defaults fetch the flake-locked revs,
per the gen root-file convention — the shape gen-demand and gen-graph already use, and the shape
gen-prelude and gen-algebra do not need for the same reason gen-memo does not yet.

**Roster.** gen-memo is **not** in the hub roster (`gen/lib/mkGenLibs.nix` has no `memo` entry) and
has **no stratum**. The stratum declaration there is total and explicit by design — a member with no
entry is a build error, never a member of an implicit residue bucket — so assigning one is a design
decision rather than scaffolding. Since the plane is none of `modules`, `aspects` or `framework`,
"substrate by elimination" is precisely the silent default that declaration exists to forbid.
gen-vars and gen-rebuild sit off the roster on the same footing. Consume via `inputs.gen-memo.lib`,
never through `mkGenLibs`.

## API Surface

**Empty.** There is nothing to document, and the empty state is itself asserted:

```sh
nix eval --json --expr 'builtins.attrNames (import ./lib)'
# []
```

## Laws (test-group mapping)

| Group | Law | Covers |
|---|---|---|
| `purity` | — | `lib/**.nix` + `flake.nix` + `default.nix` are free of `nixpkgs`, `lib.`, `{ lib }`/`{ lib,`, `evalModules`, `mkOption`. Carries an in-suite positive control asserting the token predicate matches a string that *does* contain a forbidden token, and a non-vacuity assertion that the scan read non-empty sources |
| `surface` | — | The export surface is empty; the standalone root entry and the `lib/` entry are one value |

Both the purity scan's reach and the collection predicate were armed during scaffolding: injecting
`{ lib }: lib.id` into `lib/default.nix` fails the purity cell naming both tokens, and dropping a
cell's `test-` prefix silently reduces the run to 4/4 green. `AGENTS.md` carries the evidence and the
both-ways reconciliation command.

## Compat / purity

- `lib/` is `nixpkgs.lib`-free; `nixpkgs` enters only in `ci/` (nix-unit harness + treefmt).
- The root flake declares zero inputs and therefore ships **no root `flake.lock`** — a consequence of
  the input set, not an omission. `ci/flake.lock` is the only lock, and it is what CI runs from.
- `ci/flake.nix` pins exactly two inputs: `gen` (the shared CI wrapper) and `nixpkgs` (harness and
  formatter). Every other input the shared runner needs — `nix-unit`, `flake-parts`, `treefmt-nix`,
  `devshell`, `flake-root`, `git-hooks-nix`, `import-tree`, `gen-prelude` — resolves through the hub's
  own pins rather than being re-declared here.
