# gen-memo — Canonical Reference

**Source of truth:** [github:sini/gen-memo](https://github.com/sini/gen-memo)
**Status:** SCAFFOLD — repository shell, empty export surface
**Last audited:** 2026-08-10

**Why this file is in the repository root, and why there is no papers copy.** Root-only is the
majority form for a *new* gen library, not a departure from one. Among the sibling `gen-*` repos
first committed on or after 2026-07-05, five of seven carry a root `REFERENCE.md`
(gen-demand, gen-edge, gen-pipe, gen-product, gen-settings; gen-link and gen-lsp are the
exceptions), and four of those five have no `papers/den-architecture/gen-specs/<lib>/` directory at
all. No `gen-specs/gen-memo/` entry was created here, and that is the precedented shape rather than
an oversight — `gen-memo` occurs 0 times in `gen-specs/ECOSYSTEM.md` (live control: `gen-graph`
occurs 13 times in the same file, same run), so nothing there points at a missing entry.

This is **not** a migration away from the papers tree. Measured against that story and refuting it:
exactly one `gen-specs/*/REFERENCE.md` has ever been deleted — `gen-derive`, a rename artefact,
since gen-derive became gen-dispatch — with a live control finding 19 adds under
`--diff-filter=A`; and gen-pipe and gen-select each carry **both** copies as *different* documents
(gen-pipe 424 root lines against 256 in papers; gen-select 223 against 376). That is a split with
active divergence. Keeping one copy, in the repo the code will land in, is what avoids joining it.

```sh
# the placement measurement, re-runnable
cd ~/Documents/papers/den-architecture
git log --diff-filter=D --name-only --format= -- 'gen-specs/*/REFERENCE.md' | grep REFERENCE.md
git log --diff-filter=A --name-only --format= -- 'gen-specs/*/REFERENCE.md' | grep -c REFERENCE.md
```

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

**This section is the canonical provenance statement for gen-memo.** `AGENTS.md` and `README.md`
restate these two entries and add nothing to them; where any of the three disagree, this one is
right.

**Nothing here is implemented.** The relationship column reads *Claimed, unrealized* for every row.
It is not *Implements* — that is false on its face for a library whose export surface is empty — and
not *Informed by*, which would understate what the first content is answerable to. The claim is
recorded up front precisely so it cannot be quietly exchanged for a weaker one once code arrives.

| Claim | Source | Relationship |
|---|---|---|
| The scheduler/rebuilder decomposition; the plane is the **rebuilder** dimension, and the scheduler is Nix's own laziness, which the evaluator already takes | Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte* | **Claimed, unrealized.** The cell in the paper's own Table 2 is *suspending* scheduler (§4.1.3) × *verifying traces* (§4.2.2). That is deliberately **not** the paper's own Nix row, which is `nix = suspending dctRebuilder` — deep constructive traces (§4.2.4). The difference is load-bearing rather than cosmetic: §4.2.2 states that all traces *except* deep traces support early cutoff, and the cutoff is exactly what the invalidation claim below needs. gen-rebuild's spike recorded §4.2.4 as an expected no-go (`spike/vsummary.nix`) |
| The invalidation relation: the AFFECTED set and the unchanged-value cutoff | Reps, Teitelbaum & Demers (1983) | **Claimed, unrealized.** Reverse-transitive-dependency propagation. AFFECTED and `O(\|AFFECTED\|)` optimality are §4.3 (*Suboptimal Behavior*); the cutoff — reevaluating an attribute instance to a value equal to its old value means changes need not be propagated further — is §4.1 (*Change Propagation*). True `O(\|AFFECTED\|)` optimality and characteristic graphs are recorded as **not reached** in pure evaluation; that finding travels with the content rather than being re-opened by the move |

**Open precondition on the Mokhov claim — unsettled, and load-bearing.** A Mokhov rebuilder consults
*persistent build information*. §3.1 defines the store as also containing "information maintained by
the build system itself, which persists from one invocation of the build system to the next — its
'memory'", and §4.2.2 says of the verifying trace specifically that "since the verifying trace
persists from one build to the next — it constitutes the build system's 'memory'". **A pure Nix
evaluation has no cross-invocation persistence.** The plane therefore claims a component defined by
consulting information it has no established means of carrying, and how that information is carried
is part of the plane's spec rather than a detail of its implementation. gen-rebuild records the
matching limit on the RTD side and this repository carries that forward; the Mokhov-side
precondition is the one that governs here, and it is open.

**Deliberately not restated: gen-rebuild's wider reading.** gen-rebuild lists seven further
*Informed by* sources against code that exists. That set belongs to the content and travels with it
when the content moves. Reproducing an arbitrary slice of another repository's provenance against no
code of our own is a claim this repository has not earned — so the lone Acar et al. (2002) row that
stood here at `aa77f7e` is removed, and the removal is recorded here so it is not re-added by
inheritance.

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
decision rather than scaffolding.

`mkGenLibs.nix` documents **five** buckets, not four: `substrate`, `modules`, `aspects`,
`framework`, and `retiring` — the last being "on the roster and leaving it: its content is moving to
another member", carried today by `resolve`, `flake`, `edge`, `demand` and `pipe`. The plane is none
of `modules`, `aspects` or `framework`; nor is it `retiring`, which describes a member on its way
off the roster rather than one that was never on it — the plane is the *destination* of three of
those five retirements. The elimination therefore still terminates at "substrate by default", which
is precisely the silent choice that declaration exists to forbid, and the conclusion is unchanged:
the stratum needs a ruling and does not get one here. gen-vars and gen-rebuild sit off the roster on
the same footing. Consume via `inputs.gen-memo.lib`, never through `mkGenLibs`.

## API Surface

**Empty.** There is nothing to document, and the empty state is itself asserted. The drift check,
run from the repository root:

```sh
nix eval --json .#lib --apply builtins.attrNames
```

```json
[]
```

The flake-ref form is required, not stylistic. The `--expr` form over a relative path fails outright
under the default pure evaluation mode — *"access to absolute path '…/gen-memo/lib' is forbidden in
pure evaluation mode (use '--impure' to override)"*, exit 1 — so `--impure` is what makes that form
run at all. gen-graph, gen-product, gen-algebra, gen-prelude and gen-settings all back their exports
section with the same `.#lib --apply` flake-ref form. `AGENTS.md` carries the failing command
verbatim.

## Laws (test-group mapping)

| Group | Law | Covers |
|---|---|---|
| `purity` | — | `lib/**.nix` + `flake.nix` + `default.nix` are free of `nixpkgs`, `lib.`, `{ lib }`/`{ lib,`, `evalModules`, `mkOption`. Violation labels are repo-root-relative (`lib/default.nix` vs `default.nix`), because `readDir` yields bare basenames and the two files would otherwise be indistinguishable in the report. Carries an in-suite positive control asserting the token predicate matches a string that *does* contain a forbidden token, and a non-vacuity assertion that the scan read non-empty sources |
| `surface` | — | The export surface is empty; the standalone root entry and the `lib/` entry are one value |

Both the purity scan's reach and the collection predicate were armed: injecting `{ lib }: lib.id`
into `lib/default.nix` **and** into the root `default.nix` in one run fails the purity cell with four
distinctly-labelled violations, and dropping a cell's `test-` prefix reduces the nix-unit run to 4/4
green while `nix flake check` still catches it. `AGENTS.md` carries the evidence and the both-ways
reconciliation command.

## Compat / purity

- `lib/` is `nixpkgs.lib`-free; `nixpkgs` enters only in `ci/` (nix-unit harness + treefmt).
- The root flake declares zero inputs and therefore ships **no root `flake.lock`** — a consequence of
  the input set, not an omission. `ci/flake.lock` is the only lock, and it is what CI runs from.
- `ci/flake.nix` pins exactly two inputs: `gen` (the shared CI wrapper) and `nixpkgs` (harness and
  formatter). Every other input the shared runner needs — `nix-unit`, `flake-parts`, `treefmt-nix`,
  `devshell`, `flake-root`, `git-hooks-nix`, `import-tree`, `gen-prelude` — resolves through the hub's
  own pins rather than being re-declared here.
- gen-memo therefore adds **one** edge to the hand-maintained sibling-pin graph: the `gen` pin
  itself, and no sibling library at all. Counting `^\s*gen[a-z-]*\.url\s*=` in each sibling's
  `ci/flake.nix`, gen-memo's 1 is matched exactly by gen-algebra and gen-prelude — the same two
  libraries whose zero-input root shape gen-memo takes. Across the other 23 sibling repos the count
  runs 1 to 9 with both median and mode 3, and only four (gen-resolve, gen-flake, gen-settings,
  gen-link) sit at 6 or above.
