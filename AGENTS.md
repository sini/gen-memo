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
implicit residue bucket" — so assigning a stratum is a design decision. The buckets are **five**,
not four: `substrate` / `modules` / `aspects` / `framework` / `retiring`, the last carried today by
`resolve`, `flake`, `edge`, `demand` and `pipe`. The plane is none of `modules`, `aspects` or
`framework`, and it is not `retiring` either — that bucket is for a member on its way *off* the
roster, and the plane is the destination of two of those five retirements rather than one of them.
So the elimination still lands on "substrate by default", exactly the silent choice the roster
forbids reading as a decision, and the stratum still needs a ruling. gen-vars and gen-rebuild sit
off the roster on the same footing. Consume via `inputs.gen-memo.lib`, never through `mkGenLibs`.

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
That is the intended behaviour: it obliges the author to state the new surface here and in the
canonical reference (`papers/den-architecture/gen-specs/gen-memo/REFERENCE.md`) in the same change,
rather than widening the library silently.

## Entry points by task

While the surface is empty the tasks are about the repository, not the library.

| Task | Reach for |
|---|---|
| Run the suite | `nix flake check ./ci` — the command CI runs (`.github/workflows/ci.yml`, `working-directory: ci`) |
| Run the suite as nix-unit, or one suite | `nix-unit --flake ./ci#tests` · `nix-unit --flake ./ci#tests.purity` |
| Get a shell with the locked nix-unit, plus `ci` / `fmt` / `repl` commands | `nix develop ./ci` (or `direnv allow` — `.envrc` is `use flake ./ci`) |
| Open the REPL | `nix repl --impure --file ci/repl.nix` |
| Format | `cd ci && nix fmt -- --ci` |
| Add the first export | Write it in `lib/`, then update `ci/tests/surface.nix`, this sheet's **Exports** section, and `papers/den-architecture/gen-specs/gen-memo/REFERENCE.md` — the surface test fails until you do |
| Read or amend the reference spec | `papers/den-architecture/gen-specs/gen-memo/REFERENCE.md` — it is **not** in this repo; specs live in the papers repo |
| Find where the plane's content lives *today* | `gen-rebuild` (store, trace, dirty cone), `gen-resolve` (`lib/override.nix`, the warm half of `lib/resolve.nix`), `gen-flake` (compose warm/override/trace) |
| Learn the plane's obligations before writing any of it | The execution-engine ADR (the plane's definition and what retires into it) and the gen-flake dissolution ADR (what arrives from there, and the two hedges that travel as spec inputs rather than as code) |

## Measured traps

Every row was measured in this repository during the scaffolding run, at the commit this sheet ships
in. Commands are given so each is re-runnable rather than trusted.

| Trap | Evidence |
|---|---|
| **`AGENTS.md` and `.envrc` both match a GLOBAL gitignore** — a plain `git add` silently adds neither. `git add -f` is needed on the **first** add only; once tracked they stage normally | `git check-ignore -v --no-index AGENTS.md .envrc README.md .gitignore` in a sibling lib reports `~/.config/git/ignore:22:/AGENTS.md` and `~/.config/git/ignore:18:.envrc`, and reports **nothing** for `README.md` / `.gitignore` — so the predicate discriminates rather than matching everything. The `.envrc` rule is the less obvious of the two |
| **`git check-ignore` WITHOUT `--no-index` is a false negative**: it skips tracked paths, so it reports clean for exactly the files whose rule you are trying to confirm | Same two paths in a repo where both are tracked: without `--no-index`, empty output and **exit 1**; with it, both rules named and exit 0. Never confirm an ignore rule with `core.excludesfile` either — an empty value there proves nothing |
| **A cross-repo conformance sweep must ask `git ls-files`, never `test -e`** — because of the rule above, a globally-ignored file can sit on disk *untracked*, which is present to the filesystem and absent to every clone. The two predicates give different answers and only the git one means "the library ships this" | Measured over the 23 sibling `gen-*` repos, same run: `test -e .envrc` ⇒ **14** present, `git ls-files .envrc` ⇒ **13**. The single discriminating repo is `gen-rebuild`, which has an `.envrc` on disk that `git ls-files` does not report. Controls in the same run: `git ls-files zzz-nope.md` ⇒ 0/24, `git ls-files flake.nix` ⇒ 24/24, so the predicate both discriminates and is live |
| **`ci/repl.nix` must ship even though this library is empty** — the hub's shared devshell hardcodes a `repl` command pointing at it, so omitting the file ships a devshell command that is broken on invocation. This is the reason to keep it, and it does not depend on how many siblings happen to have one | `gen/ci/flakeModule.nix:158-164` defines `{ name = "repl"; command = ''nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"''; }`, inherited by every library that takes `mkCi`. Tracked in 13 of the 23 siblings by `git ls-files`, but the count is not the argument |
| **nix-unit collects only cells named `test-*`. A cell that loses the prefix vanishes from the nix-unit run, which reports GREEN** — the count moves 5/5 → 4/4. It is **backstopped by `nix flake check`**, which is the command CI actually runs: `checks.default` is gen's homegrown asserter and does not filter on the prefix, so it still collects and asserts the cell. The exposure is real for nix-unit and only for nix-unit | Armed with the prefix dropped **and** the expectation broken (`test-lib-exports-nothing` → `lib-exports-nothing`, `expected = [ "sentinel" ]`), one tree, both oracles: `nix-unit --flake ./ci#tests` ⇒ `🎉 4/4 successful`, **exit 0** — the cell is simply gone; `nix flake check` from `ci/` ⇒ **exit 1**, `error: FAIL surface.lib-exports-nothing: got [], expected ["sentinel"]`. Still reconcile declared-vs-collected **both ways** rather than reading the nix-unit count: `grep -rhoE '\btest-[a-z0-9-]+' ci/tests/ \| sort` against the run's own names, through `comm -23` and `comm -13`. On the armed run the first arm named `test-lib-exports-nothing`; on a clean run both are empty |
| **An untracked file under `ci/tests/` is invisible to the flake — including a deliberately failing one.** New test files must be `git add`ed before any `nix` invocation, or the run is green about a tree that does not contain them | A probe file asserting `expr = 1; expected = 2;` was written to `ci/tests/` and left untracked: `🎉 5/5 successful`, exit 0. Positive control, same file, same run afterwards: `git add` it and the suite reports `😢 5/6`, exit 1, naming `staging.test-untracked-file-is-invisible`. The green was invisibility, not absence |
| **`nix flake check` and nix-unit are different oracles.** `checks.default` is a homegrown asserter, and nix-unit's `expectedError` is unassertable — so a guard cannot be tested for its own firing, and no check whose failure cannot be observed belongs in this suite | Both were armed here. Breaking one expectation: `nix flake check` (cwd `ci/`, the workflow's own command) exits **1** with `error: FAIL surface.test-lib-exports-nothing: got [], expected ["sentinel"]`; `nix-unit --flake ./ci#tests` exits **1** with `😢 4/5`. Both catch a wrong value; neither can assert that a *throw* happened |
| **A bare-leaf nix-unit target reports `0/0` — a false pass.** Establish a suite is non-vacuous before reading its green | This suite is 5 cells across 2 suites, and the purity scan carries its own in-suite positive control (`test-forbidden-token-scan-is-live`, which asserts the token predicate returns `[ "evalModules" ]` on a string that contains one) so its absence claim cannot pass by a dead predicate |
| **The purity scan reaches `lib/` — verified, not assumed.** An absence claim over source needs the scan armed, because an empty `lib/` or a broken `readDir` reports clean | Injecting `let _sentinel = { lib }: lib.id; in` into `lib/default.nix` failed `purity.test-library-source-is-nixpkgs-lib-free` naming both tokens: `[ "lib/default.nix: 'lib.'" "lib/default.nix: '{ lib }'" ]`, exit 1. Reverted; the suite returns to 5/5 |
| **Purity violation labels must be repo-root-relative, or two files collide under one name.** `readDir libDir` yields bare basenames, so `lib/default.nix` renders as `default.nix` — the same string as the root `default.nix` the scan appends. A violation in the library was indistinguishable from one in the root entry, and the report named a file that could not be located | Two arms, same two injections (`{ lib }: lib.id` into **both** `lib/default.nix` and the root `default.nix`), same instrument. At `aa77f7e`: `[ "default.nix: 'lib.'" "default.nix: '{ lib }'" "default.nix: 'lib.'" "default.nix: '{ lib }'" ]` — four violations, one name, two files. After the fix: `[ "lib/default.nix: 'lib.'" "lib/default.nix: '{ lib }'" "default.nix: 'lib.'" "default.nix: '{ lib }'" ]`. Both arms exit 1 at 4/5, so the discrimination is the finding, not the failure. gen-product already labels by relative path; gen-graph carries the same collision |
| **The root flake has no `flake.lock`, and that is a consequence rather than an omission** — it declares zero inputs. `ci/flake.lock` is the only lock, and it is what the acceptance run uses | `flake.nix` has no `inputs` attribute; gen-prelude and gen-algebra are the same shape and likewise ship no root lock |
| **`nix fmt -- --ci` run from a LINKED WORKTREE formats the MAIN CHECKOUT and reports green about a tree it never touched** (treefmt resolves the tree root via `.git/config`, and a worktree's `.git` is a pointer *file*). Not triggered here — this is a normal repository, not a worktree — but it will bite anyone who takes a worktree of this repo | The shared CI module sets `projectRootFile = null` precisely to select treefmt's native `git rev-parse --show-toplevel` detection for this reason; its own comment records that `--tree-root` is rejected by the wrapper and `TREEFMT_TREE_ROOT_FILE` is ignored. Verify which tree was touched (`git status`) rather than reading the formatter's exit code |

## Theory

The plane claims the **rebuilder** half of the build-systems decomposition, and only that half.

**The canonical reference spec is not in this repository.** It is
`papers/den-architecture/gen-specs/gen-memo/REFERENCE.md` — the reference spec, and every spec, lives
in the papers repo by ruling. Its § Academic Provenance is canonical; this section restates it and
adds nothing, and where the two disagree that one is right.

**That is a boundary, not just a path.** The canonical statement is no longer co-located with this
sheet, no longer versioned alongside it, and **no longer drift-checkable from here**: the papers repo
is a separate history with no CI whatsoever — it has no `.github` directory at all, against two
tracked entries under one in gen-memo. Nothing in this repository can notice if the restatement below
drifts from canon, and nothing over there can notice either. Keeping the two in agreement is a manual
obligation carried by whoever edits either, not a check that will fail. Before relying on this
section, read the canonical file.

**Claimed, unrealized** — the verb is neither *Implements* nor *Informed by*. Nothing in this
repository implements anything, so *Implements* would be false on its face; *Informed by* would
understate what the first content is answerable to. The claim is recorded up front so it cannot be
quietly exchanged for a weaker one once code arrives.

- **Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte*** — the
  scheduler/rebuilder decomposition. This plane is the **rebuilder** dimension; the scheduler is
  Nix's own laziness, taken by the evaluator, so no scheduling belongs here. Named against the
  paper's own Table 2, the claimed cell is **suspending** scheduler (§4.1.3) × **verifying traces**
  (§4.2.2) — `verifyVT` is defined inside §4.2.2, so that is one coordinate and not two. This is
  deliberately *not* the paper's own Nix row, `nix = suspending dctRebuilder`, which is deep
  constructive traces (§4.2.4): §4.2.2 records that all traces except deep traces support early
  cutoff, and the cutoff is what the invalidation claim below needs. gen-rebuild's spike recorded
  §4.2.4 as an expected no-go. gen-rebuild realizes a verifying trace today, and that is the content
  destined to move here.
- **Reps, Teitelbaum & Demers (1983)** — reverse-transitive-dependency propagation: the AFFECTED set
  (§4.3) and the unchanged-value cutoff (§4.1) supply the invalidation relation. gen-rebuild records
  true `O(|AFFECTED|)` optimality and characteristic graphs as **not reached** in pure evaluation;
  that finding travels with the content and is not re-opened by the move.

**Open precondition, and it is load-bearing.** A Mokhov rebuilder is *defined* by consulting
persistent build information — §3.1's store "also contains information maintained by the build
system itself, which persists from one invocation of the build system to the next — its 'memory'",
and §4.2.2 says the verifying trace *is* that memory. **A pure Nix evaluation has no
cross-invocation persistence.** How the plane carries that information is part of its spec, not a
detail of its implementation, and it is unsettled. gen-rebuild records the matching limit on the RTD
side and this repository carries that forward; the Mokhov-side one is the precondition that governs
here.

**The definition, not a citation.** The plane's correctness condition is the **byte-parity oracle**:
a plane output must be byte-identical to a cold evaluation. It is a definition rather than a test
target — a plane that is fast and not byte-parity is not a faster plane, it is a wrong one.

**Checked invariant.** `lib/` is `nixpkgs.lib`-free, enforced by `ci/tests/purity.nix` over
`lib/**.nix` + `flake.nix` + `default.nix`; nixpkgs enters only in `ci/` (the nix-unit harness and
treefmt). Armed in this run — see the traps table.

## Drift check

From the repository root:

```sh
nix eval --json .#lib --apply builtins.attrNames
```

Current output (verbatim):

```json
[]
```

The flake-ref form is load-bearing, not stylistic. `nix eval --json --expr 'builtins.attrNames (import ./lib)'` **does not run**: under the default pure evaluation mode it exits 1 with *"access
to absolute path '…/gen-memo/lib' is forbidden in pure evaluation mode (use '--impure' to
override)"*, and `--impure` is what makes it work rather than what makes it strict. For a library
whose Exports section is *empty*, this command is the only instrument backing that section, so one
that cannot run is the whole defect. gen-graph, gen-product, gen-algebra, gen-prelude and
gen-settings all back their exports section with the same `.#lib --apply` flake-ref form; gen-prelude
uses this exact command.

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
