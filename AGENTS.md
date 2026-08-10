# gen-memo — agent capability sheet

## Scope

The **incremental plane**: a decision layer over the evaluator that never evaluates, only decides
**reuse**. Its definition is a byte-parity oracle against a cold evaluation — a plane output must be
byte-identical to what a cold run produces — so the plane is correct exactly when it is invisible in
the result and visible only in the work avoided.

**This repository is a SHELL. The library exports nothing.** `lib/default.nix` is `{ }`, and
`ci/tests/surface.nix` holds it there. The content this plane will hold is named but not written: the
warm fold and override cone that currently live in gen-resolve, the dirty-cone propagation that
currently lives in gen-rebuild, and gen-flake's compose warm/override/trace arm. None of it has moved,
because the interface it needs — what the evaluator exposes to the plane (node hashes, edge sets,
traces) — is a named, unsettled design item. **Read that as a fact about this repo, not as work
waiting to be picked up by whoever opens it.**

**Not in the hub roster.** `gen/lib/mkGenLibs.nix` has no `memo` entry and gen-memo has no stratum.
That is deliberate, not an oversight: the roster's stratum declaration is total and explicit by
design — its own text says "a member with no entry here is a build error, never a member of an
implicit residue bucket" — so assigning a stratum is a design decision, and the plane is none of
`modules` / `aspects` / `framework`, which makes "substrate by elimination" exactly the silent
default the roster forbids reading as a choice. gen-vars and gen-rebuild sit off the roster on the
same footing. Consume via `inputs.gen-memo.lib`, never through `mkGenLibs`.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

The plane's whole risk is re-implementing something one row below it, so this table is the sheet's
load-bearing half while the export surface is empty.

| Responsibility | Owner |
|---|---|
| **Evaluating anything at all** — forcing a node, computing a value | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs". The sole evaluator, kept thin. The plane decides *whether* to recompute; it never *is* the recompute. A caller-supplied `recompute` is the shape this takes |
| **Scheduling** — deciding what to compute and in what order | Nix's own laziness, which the evaluator already takes. In the Mokhov decomposition this library is the **rebuilder half alone**; the scheduler half is not a gen library at all, and writing one here would duplicate the language runtime |
| The static attribute-dependency schedule, and the **cold** fold | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)". Only its **warm** fold and override cone are destined for the plane; the schedule and the cold path are not |
| Result store, verifying traces, dirty propagation — **as they exist today** | `gen-rebuild` — "gen-rebuild: pure-Nix incremental rebuilder core (Mokhov rebuilder dimension)". This is the plane's own content, and it has **not moved yet**. Until it does, that code lives there and is read there. gen-rebuild's library shell retires with the move |
| Flake composition, and the warm/override/trace arm built on it | `gen-flake` — "gen-flake — the pure composition boundary of the pure-gen module ecosystem". Its compose warm/override/trace is destined here and was explicitly gated on this repository existing; gen-flake dissolves and its repo orphans as reference. `diff.nix` stays in the orphaned repo — its two hedges (function-equality blindness in `dropFns`; the four-reserved-names group misclassification) are named inputs to the plane's failure-attribution spec, not code to copy |
| Graph traversal, reverse reachability — the dependent cone as an **algorithm** | `gen-graph` — "gen-graph: accessor-based graph query combinators". The plane *reads* a cone; the traversal that computes it is never re-implemented here |
| Well-definedness and stratification **checks** | Neither the plane nor a standalone analysis library: they survive as **graph-native analysis queries** over the graph the engine already exposes, with reads derived from the graph rather than declared |
| The typed demand cascade (kinds, demands, sub-demands, provenance) | `gen-demand` — "gen-demand — typed demand cascade (kinds resolve demands into resources + wiring + sub-demands; a stratified, terminating fold resolves the multiset with full provenance)". Its folds re-express over the evaluator, **not** into this plane — an adjacent retirement, a different destination |
| Stratified layered resolution of a settings value | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct". Both fold; that is the whole resemblance |
| Fold and algebra primitives, the search monad, intensional functions | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either" |
| General list/attr utilities | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem" |

**The one construction error to avoid.** *A plane that accumulates its own evaluation state has
failed.* The plane observes the evaluator's graph and decides against it; it does not become a second
place where evaluation results live and drift. A "cache" written here that is not defined by the
byte-parity oracle is that failure, whatever it is named.

## Exports

**None.** `import ./lib` is `{ }`, and so is `inputs.gen-memo.lib`.

Entry, once there is something to enter: `inputs.gen-memo.lib` (flake) — `import ./lib`. The root
`default.nix` is the lib **value**, not a function, because gen-memo declares no inputs; gen-prelude
and gen-algebra ship the same shape. When the plane acquires dependencies, `default.nix` becomes a
function whose defaults fetch the flake-locked revs, per the gen root-file convention.

`ci/tests/surface.nix` asserts the empty surface, so **the first export arrives as a failing test**.
That is the intended behaviour: it obliges the author to state the new surface here and in
`REFERENCE.md` in the same change, rather than widening the library silently.

## Entry points by task

While the surface is empty the tasks are about the repository, not the library.

| Task | Reach for |
|---|---|
| Run the suite | `nix flake check ./ci` — the command CI runs (`.github/workflows/ci.yml`, `working-directory: ci`) |
| Run the suite as nix-unit, or one suite | `nix-unit --flake ./ci#tests` · `nix-unit --flake ./ci#tests.purity` |
| Get a shell with the locked nix-unit, plus `ci` / `fmt` / `repl` commands | `nix develop ./ci` (or `direnv allow` — `.envrc` is `use flake ./ci`) |
| Open the REPL | `nix repl --impure --file ci/repl.nix` |
| Format | `cd ci && nix fmt -- --ci` |
| Add the first export | Write it in `lib/`, then update `ci/tests/surface.nix`, this sheet's **Exports** section, and `REFERENCE.md` — the surface test fails until you do |
| Find where the plane's content lives *today* | `gen-rebuild` (store, trace, dirty cone), `gen-resolve` (`lib/override.nix`, the warm half of `lib/resolve.nix`), `gen-flake` (compose warm/override/trace) |
| Learn the plane's obligations before writing any of it | The execution-engine ADR (the plane's definition and what retires into it) and the gen-flake dissolution ADR (what arrives from there, and the two hedges that travel as spec inputs rather than as code) |

## Measured traps

Every row was measured in this repository during the scaffolding run, at the commit this sheet ships
in. Commands are given so each is re-runnable rather than trusted.

| Trap | Evidence |
|---|---|
| **`AGENTS.md` and `.envrc` both match a GLOBAL gitignore** — a plain `git add` silently adds neither. `git add -f` is needed on the **first** add only; once tracked they stage normally | `git check-ignore -v --no-index AGENTS.md .envrc README.md .gitignore` in a sibling lib reports `~/.config/git/ignore:22:/AGENTS.md` and `~/.config/git/ignore:18:.envrc`, and reports **nothing** for `README.md` / `.gitignore` — so the predicate discriminates rather than matching everything. The `.envrc` rule is the less obvious of the two |
| **`git check-ignore` WITHOUT `--no-index` is a false negative**: it skips tracked paths, so it reports clean for exactly the files whose rule you are trying to confirm | Same two paths in a repo where both are tracked: without `--no-index`, empty output and **exit 1**; with it, both rules named and exit 0. Never confirm an ignore rule with `core.excludesfile` either — an empty value there proves nothing |
| **nix-unit collects only cells named `test-*`. A cell that loses the prefix vanishes and the run reports GREEN** — the count moves 5/5 → 4/4 with no diagnostic anywhere | Renaming `test-lib-exports-nothing` to `lib-exports-nothing` and re-running gave `🎉 4/4 successful`, exit 0. Reconcile declared-vs-collected **both ways** rather than reading the count: `grep -rhoE '\btest-[a-z0-9-]+' ci/tests/ \| sort` against the run's own names, through `comm -23` and `comm -13`. On the armed run the first arm named `test-lib-exports-nothing`; on a clean run both are empty |
| **An untracked file under `ci/tests/` is invisible to the flake — including a deliberately failing one.** New test files must be `git add`ed before any `nix` invocation, or the run is green about a tree that does not contain them | A probe file asserting `expr = 1; expected = 2;` was written to `ci/tests/` and left untracked: `🎉 5/5 successful`, exit 0. Positive control, same file, same run afterwards: `git add` it and the suite reports `😢 5/6`, exit 1, naming `staging.test-untracked-file-is-invisible`. The green was invisibility, not absence |
| **`nix flake check` and nix-unit are different oracles.** `checks.default` is a homegrown asserter, and nix-unit's `expectedError` is unassertable — so a guard cannot be tested for its own firing, and no check whose failure cannot be observed belongs in this suite | Both were armed here. Breaking one expectation: `nix flake check` (cwd `ci/`, the workflow's own command) exits **1** with `error: FAIL surface.test-lib-exports-nothing: got [], expected ["sentinel"]`; `nix-unit --flake ./ci#tests` exits **1** with `😢 4/5`. Both catch a wrong value; neither can assert that a *throw* happened |
| **A bare-leaf nix-unit target reports `0/0` — a false pass.** Establish a suite is non-vacuous before reading its green | This suite is 5 cells across 2 suites, and the purity scan carries its own in-suite positive control (`test-forbidden-token-scan-is-live`, which asserts the token predicate returns `[ "evalModules" ]` on a string that contains one) so its absence claim cannot pass by a dead predicate |
| **The purity scan reaches `lib/` — verified, not assumed.** An absence claim over source needs the scan armed, because an empty `lib/` or a broken `readDir` reports clean | Injecting `let _sentinel = { lib }: lib.id; in` into `lib/default.nix` failed `purity.test-library-source-is-nixpkgs-lib-free` naming both tokens: `[ "default.nix: 'lib.'" "default.nix: '{ lib }'" ]`. Reverted; the suite returns to 5/5 |
| **The root flake has no `flake.lock`, and that is a consequence rather than an omission** — it declares zero inputs. `ci/flake.lock` is the only lock, and it is what the acceptance run uses | `flake.nix` has no `inputs` attribute; gen-prelude and gen-algebra are the same shape and likewise ship no root lock. The 20 libs that do have one all declare inputs |
| **`nix fmt -- --ci` run from a LINKED WORKTREE formats the MAIN CHECKOUT and reports green about a tree it never touched** (treefmt resolves the tree root via `.git/config`, and a worktree's `.git` is a pointer *file*). Not triggered here — this is a normal repository, not a worktree — but it will bite anyone who takes a worktree of this repo | The shared CI module sets `projectRootFile = null` precisely to select treefmt's native `git rev-parse --show-toplevel` detection for this reason; its own comment records that `--tree-root` is rejected by the wrapper and `TREEFMT_TREE_ROOT_FILE` is ignored. Verify which tree was touched (`git status`) rather than reading the formatter's exit code |

## Theory

The plane claims the **rebuilder** half of the build-systems decomposition, and only that half.

**Implements** *(claimed by this repository's design; no code yet realizes it — the claim is what the
first content is answerable to, and is recorded here so it cannot be quietly swapped)*

- **Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte*** — the
  scheduler/rebuilder decomposition. This plane is the **rebuilder** dimension; the scheduler is
  Nix's own laziness, taken by the evaluator, so no scheduling belongs here. The same paper grounds
  gen-rebuild today (flat relocatable store §3.1, verifying trace §4.2.2, `verify` §4.2), which is
  the content destined to move here.
- **Reps, Teitelbaum & Demers (1983)** — reverse-transitive-dependency propagation: the AFFECTED set
  (§4.3) and the unchanged-value cutoff (§4.1) supply the invalidation relation. gen-rebuild records
  true `O(|AFFECTED|)` optimality and characteristic graphs as **not reached** in pure evaluation;
  that finding travels with the content and is not re-opened by the move.

**The definition, not a citation.** The plane's correctness condition is the **byte-parity oracle**:
a plane output must be byte-identical to a cold evaluation. It is a definition rather than a test
target — a plane that is fast and not byte-parity is not a faster plane, it is a wrong one.

**Checked invariant.** `lib/` is `nixpkgs.lib`-free, enforced by `ci/tests/purity.nix` over
`lib/**.nix` + `flake.nix` + `default.nix`; nixpkgs enters only in `ci/` (the nix-unit harness and
treefmt). Armed in this run — see the traps table.

## Drift check

```sh
nix eval --json --expr 'builtins.attrNames (import ./lib)'
```

Current output (verbatim):

```json
[]
```

Reconcile the suite's declared cells against its collected ones, **both directions** — a `test-`
prefix lost in an edit reports green:

```sh
grep -rhoE '\btest-[a-z0-9-]+' ci/tests/ | sort > /tmp/declared
nix-unit --flake ./ci#tests | grep -oE 'test-[a-z0-9-]+' | sort > /tmp/collected
comm -23 /tmp/declared /tmp/collected   # declared but not collected — the silent-green case
comm -13 /tmp/declared /tmp/collected   # collected but not declared
```

Both are empty at this revision; the run is 5/5.

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with
`working-directory: ci`):

```sh
nix flake check ./ci
```
