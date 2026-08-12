# gen-memo — agent capability sheet

## Scope

The **incremental plane**: a decision layer over the evaluator that never evaluates, only decides
**reuse**. Its definition is a byte-parity oracle against a cold evaluation — a plane output must be
byte-identical to what a cold run produces — so the plane is correct exactly when it is invisible in
the result and visible only in the work avoided.

**The dirty-cone content has LANDED; two pieces have not.** What is here: the flat relocatable result
store and its verifying trace, the three reuse predicates, the dirty cone and the exact affected set,
the change/propagate split with its fused override, the cut-heavy eager push, the structural deltas,
the provenance reads, and the per-SCC solver — 24 exports, arrived from the retiring rebuilder
library whose shell and name retire with them. What is still elsewhere: the **warm fold and override
cone** in gen-resolve, and gen-flake's **compose warm/override/trace** arm. Each is its own sequenced
piece of work.

The interface to the evaluator is **settled and built in the evaluator**: the plane returns a
`Decision` of two total functions and no values, reads through a restricted facade of exactly
`get` / `nodeIds` / `resolutional`, and never receives a structural value from a prior evaluation.
The content here predates that interface and is consumed the way it always was — a caller-supplied
`recompute` and an accessor — so re-expressing it onto the `Decision` facade is outstanding work and
not something this sheet claims is done.

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

The plane's whole risk is re-implementing something one row below it, and that risk went UP rather
than down when content landed: the library now has combinators of its own, and the tempting shortcut
is always to write a small local version of something a row below rather than consume it.

| Responsibility | Owner |
|---|---|
| **Evaluating anything at all** — forcing a node, computing a value | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs". The sole evaluator, kept thin. The plane decides *whether* to recompute; it never *is* the recompute. A caller-supplied `recompute` is the shape this takes |
| **Scheduling** — deciding what to compute and in what order | Nix's own laziness, which the evaluator already takes. In the Mokhov decomposition this library is the **rebuilder half alone**; the scheduler half is not a gen library at all, and writing one here would duplicate the language runtime |
| The static attribute-dependency schedule, and the **cold** fold | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)". Only its **warm** fold and override cone are destined for the plane; the schedule and the cold path are not |
| Result store, verifying traces, dirty propagation | **This library.** They arrived from the retiring rebuilder core, whose shell and name retire with them; the origin repository is history rather than a place to read the current definition |
| Flake composition, and the warm/override/trace arm built on it | `gen-flake` — "gen-flake — the pure composition boundary of the pure-gen module ecosystem". Its compose warm/override/trace is destined here and was explicitly gated on this repository existing; gen-flake dissolves and its repo orphans as reference. `diff.nix` stays in the orphaned repo — its two hedges (function-equality blindness in `dropFns`; the four-reserved-names group misclassification) are named inputs to the plane's failure-attribution spec, not code to copy |
| Graph traversal, reverse reachability, the SCC partition — the dependent cone and the quotient as **algorithms** | `gen-graph` — "gen-graph: accessor-based graph query combinators". The plane *reads* a cone and *reads* a partition through the one published door; neither traversal is re-implemented here. `dependentsOf` / `reachableFrom` / `coneRank` / `directDependents` / `condensation` are all consumed, never mirrored |
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

Entry: `inputs.gen-memo.lib` (flake), or the root `default.nix` — a **function** of
`{ prelude, graph }`, per the gen root-file convention, since the plane now has dependencies.

**24 exports, in five groups.**

| Group | Exports |
|---|---|
| Build and reuse decision | `build` · `needsEval` · `earlyCutoff` · `verify` |
| Cones | `affected` · `impactOf` · `dirtySet` · `affectedSet` |
| Change and propagate | `applyDelta` · `batch` · `propagate` · `override` · `force` · `forceCtx` · `propagateEager` |
| Topology change | `mkAccessor` · `retract` · `applyEdgeDelta` |
| Cycles and provenance | `runScc` · `restabilize` · `support` · `supportDirect` · `why` · `whyNot` |

`needsEval` / `earlyCutoff` / `verify` decide at three DIFFERENT times — before recompute, after
recompute, and against the stored trace. They are not one predicate under three names, and collapsing
them loses the precision story.

**NOT exported, and deliberately:** `hashGuarded` / `hashEq` / `hashMoved` (`lib/hash.nix`) and
`mergeExports` (`lib/merge.nix`). `lib/default.nix` folds neither file in; the files that need them
import them directly. The plane hashes for its own reuse decision, and the evaluator it decides for
is owed no hash surface at all — putting them on the list would be a new surface arriving under cover
of a move.

`ci/tests/surface.nix` pins the surface exactly, so **a widening — or a silent loss — arrives as a
failing test**. That obliges the author to state the change here and in the canonical reference
(`papers/den-architecture/gen-specs/gen-memo/REFERENCE.md`) in the same change, rather than moving the
library's surface silently.

## Entry points by task

| Task | Reach for |
|---|---|
| Full evaluation into a store and trace | `build { accessor; recompute; hashOf; fixpoint ? null }` — `lib/build.nix`. `fixpoint` switches on the cyclic path |
| Re-evaluate after a data change | `override ctx id newDecls` (`lib/drivers.nix`, the fused propagate-after-applyDelta). Cyclic graphs: `restabilize` |
| Re-evaluate after a localized, cut-heavy edit | `propagateEager ctx changes` — `lib/eager.nix`. Opt-in; `propagate` stays the general default |
| Change the topology | `retract` / `applyEdgeDelta` — `lib/structural.nix`. `override` is data-change only and cannot express it |
| Ask why a node was or was not recomputed | `why` / `whyNot` — `lib/provenance.nix`. `whyNot` is total over all three verdicts |
| See it run end to end | `nix eval -f examples/dag` — the cone, the reuse, the poisoned-recompute proof and the located cycle blame, as one record |
| Run the suite | `nix flake check ./ci` — the command CI runs (`.github/workflows/ci.yml`, `working-directory: ci`) |
| Run the suite as nix-unit, or one suite | `nix-unit --flake ./ci#tests` · `nix-unit --flake ./ci#tests.purity` |
| Get a shell with the locked nix-unit, plus `ci` / `fmt` / `repl` commands | `nix develop ./ci` (or `direnv allow` — `.envrc` is `use flake ./ci`) |
| Open the REPL | `nix repl --impure --file ci/repl.nix` |
| Format | `cd ci && nix fmt -- --ci` |
| Change the export surface | Write it in `lib/`, then update `ci/tests/surface.nix`, this sheet's **Exports** section, and `papers/den-architecture/gen-specs/gen-memo/REFERENCE.md` — the surface test fails until you do. Adding a module also means the fold: a name already taken is a REFUSAL, not a shadow |
| Read or amend the reference spec | `papers/den-architecture/gen-specs/gen-memo/REFERENCE.md` — it is **not** in this repo; specs live in the papers repo |
| Find the content that has NOT arrived yet | `gen-resolve` (`lib/override.nix`, the warm half of `lib/resolve.nix`), `gen-flake` (compose warm/override/trace) |
| Learn the plane's obligations before extending it | The execution-engine ADR (the plane's definition and what retires into it) and the gen-flake dissolution ADR (what arrives from there, and the two hedges that travel as spec inputs rather than as code) |

## Measured traps

Every row was measured in this repository — the first two during the migration that brought the
plane's content in, the rest during the scaffolding run before it. Commands are given so each is
re-runnable rather than trusted.

| Trap | Evidence |
|---|---|
| **A NIX DERIVATION CANNOT BE A NODE VALUE.** `lib/hash.nix`'s `containsFunction` walks a value structurally with no cycle guard, and a derivation is SELF-REFERENTIAL — so the guard descends forever and aborts with a stack overflow `builtins.tryEval` DOES NOT CATCH. Unlike the null-hash rule, this partiality is not conservative: it does not fall back to always-dirty, it takes the evaluation down. No cell can pin it for the same reason | `(builtins.elemAt drv.all 0) == drv` ⇒ **true**, and `drv`'s keys are `all args builder drvAttrs drvPath name out outPath outputName system type`. `(builtins.tryEval (containsFunction drv)).success` does not return a value at all — the run ends with `error: stack overflow; max-call-depth exceeded`. Live controls, same predicate, same run: `containsFunction { a = x: x; }` ⇒ `true`, `containsFunction { a = 1; b = [ 2 3 ]; }` ⇒ `false`, so the predicate discriminates on values it can decide. `ci/tests/byte-parity.nix` carries `drvPath` values instead and records the finding in its header |
| **gen-graph's partition door publishes PLAIN DATA, so `members` and `sccOf` are MAPS and not lookup functions.** Content written against the older closure-based `condensation` calls them, and `cond.members tag` fails with "attempt to call something which is not a function but a set" — a runtime error, at the stratum fold, not at import | The door's own reasoning is that a function's identity is minted by the build that made it and cannot cross a library boundary. Both call sites here were re-expressed to `cond.members.${tag} or [ ]` and `cond.sccOf.<id>`; `ci/tests/build.nix` pins the ordering gate against the new shape and adds a cell asserting the two components are distinct and both present, since an ordering assertion over a collapsed partition reads a coincidence |
| **`AGENTS.md` and `.envrc` both match a GLOBAL gitignore** — a plain `git add` silently adds neither. `git add -f` is needed on the **first** add only; once tracked they stage normally | `git check-ignore -v --no-index AGENTS.md .envrc README.md .gitignore` in a sibling lib reports `~/.config/git/ignore:22:/AGENTS.md` and `~/.config/git/ignore:18:.envrc`, and reports **nothing** for `README.md` / `.gitignore` — so the predicate discriminates rather than matching everything. The `.envrc` rule is the less obvious of the two |
| **`git check-ignore` WITHOUT `--no-index` is a false negative**: it skips tracked paths, so it reports clean for exactly the files whose rule you are trying to confirm | Same two paths in a repo where both are tracked: without `--no-index`, empty output and **exit 1**; with it, both rules named and exit 0. Never confirm an ignore rule with `core.excludesfile` either — an empty value there proves nothing |
| **A cross-repo conformance sweep must ask `git ls-files`, never `test -e`** — because of the rule above, a globally-ignored file can sit on disk *untracked*, which is present to the filesystem and absent to every clone. The two predicates give different answers and only the git one means "the library ships this" | Measured over the 23 sibling `gen-*` repos, same run: `test -e .envrc` ⇒ **14** present, `git ls-files .envrc` ⇒ **13**. The single discriminating repo is `gen-rebuild`, which has an `.envrc` on disk that `git ls-files` does not report. Controls in the same run: `git ls-files zzz-nope.md` ⇒ 0/24, `git ls-files flake.nix` ⇒ 24/24, so the predicate both discriminates and is live |
| **`ci/repl.nix` must ship** — measured when the library was still empty, and the reason is independent of that: the hub's shared devshell hardcodes a `repl` command pointing at it, so omitting the file ships a devshell command that is broken on invocation. This is the reason to keep it, and it does not depend on how many siblings happen to have one | `gen/ci/flakeModule.nix:158-164` defines `{ name = "repl"; command = ''nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"''; }`, inherited by every library that takes `mkCi`. Tracked in 13 of the 23 siblings by `git ls-files`, but the count is not the argument |
| **nix-unit collects only cells named `test-*`. A cell that loses the prefix vanishes from the nix-unit run, which reports GREEN** — the count moves 5/5 → 4/4. It is **backstopped by `nix flake check`**, which is the command CI actually runs: `checks.default` is gen's homegrown asserter and does not filter on the prefix, so it still collects and asserts the cell. The exposure is real for nix-unit and only for nix-unit | Armed with the prefix dropped **and** the expectation broken (`test-lib-exports-nothing` → `lib-exports-nothing`, `expected = [ "sentinel" ]`), one tree, both oracles: `nix-unit --flake ./ci#tests` ⇒ `🎉 4/4 successful`, **exit 0** — the cell is simply gone; `nix flake check` from `ci/` ⇒ **exit 1**, `error: FAIL surface.lib-exports-nothing: got [], expected ["sentinel"]`. Still reconcile declared-vs-collected **both ways** rather than reading the nix-unit count — see the Drift check section for the command, whose character class must include capitals. On the armed run the first arm named `test-lib-exports-nothing`; on a clean run both are empty. Figures in this row are from the scaffolding commit, when the suite was 5 cells |
| **An untracked file under `ci/tests/` is invisible to the flake — including a deliberately failing one.** New test files must be `git add`ed before any `nix` invocation, or the run is green about a tree that does not contain them | A probe file asserting `expr = 1; expected = 2;` was written to `ci/tests/` and left untracked: `🎉 5/5 successful`, exit 0. Positive control, same file, same run afterwards: `git add` it and the suite reports `😢 5/6`, exit 1, naming `staging.test-untracked-file-is-invisible`. The green was invisibility, not absence |
| **`nix flake check` and nix-unit are different oracles.** `checks.default` is a homegrown asserter, and nix-unit's `expectedError` is unassertable — so a guard cannot be tested for its own firing, and no check whose failure cannot be observed belongs in this suite | Both were armed here. Breaking one expectation: `nix flake check` (cwd `ci/`, the workflow's own command) exits **1** with `error: FAIL surface.test-lib-exports-nothing: got [], expected ["sentinel"]`; `nix-unit --flake ./ci#tests` exits **1** with `😢 4/5`. Both catch a wrong value; neither can assert that a *throw* happened |
| **A bare-leaf nix-unit target reports `0/0` — a false pass.** Establish a suite is non-vacuous before reading its green | This suite is 5 cells across 2 suites, and the purity scan carries its own in-suite positive control (`test-forbidden-token-scan-is-live`, which asserts the token predicate returns `[ "evalModules" ]` on a string that contains one) so its absence claim cannot pass by a dead predicate |
| **The purity scan reaches `lib/` — verified, not assumed.** An absence claim over source needs the scan armed, because an empty `lib/` or a broken `readDir` reports clean | Injecting `let _sentinel = { lib }: lib.id; in` into `lib/default.nix` failed `purity.test-library-source-is-nixpkgs-lib-free` naming both tokens: `[ "lib/default.nix: 'lib.'" "lib/default.nix: '{ lib }'" ]`, exit 1. Reverted. Measured at the scaffolding commit, when the suite was 5 cells |
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

**IMPLEMENTED, with the citations' provenance stated separately from the citations.** The content
below is realized in `lib/`; what varies is how well each attribution is backed, and that is a
different axis from whether the code exists.

**★ CITATION PROVENANCE.** Every primary cited **with a section coordinate** is in the papers archive
and each such coordinate was located in that source, not carried on the retiring library's authority.
`lib/default.nix` states this once for every file below it, with the coordinates enumerated and both
excluded axes named.

**Excluded axis 1 — four cited names are in NEITHER archive tier:** Tarjan 1972, Kosaraju/Sharir,
Magnusson–Hedin, Kleene ⇒ 0 across `used/` and `reference-catalog/`, against the eight archived names
as live controls in the same run. None carries a section coordinate; each is an attribution to a named
idea and is not to be read as checked.

**Excluded axis 2 — "located in that source" means BY CONTENT, not by heading.** The Acar extraction
has no numbered section headings (title + 47 `## Page N` markers only), so its §-digits are
content-verified and **coordinate-unverifiable** at the current extraction.

★ **The splice exclusion's ground, restated.** `topolog` ⇒ 0 and `reverse` ⇒ 0 both hold, so the
conclusion stands. But `order maintenance` ⇒ 0, carried beside them, was measured with a **space**
against a **hyphenated** surface: hyphen-tolerant it is ⇒ **7**, and the paper's efficient
implementation is built on order maintenance. The retired figure implied the opposite.

**Three claims are this library's own and are attributed to no paper** — in each case because the
cited section was read and does not contain them: the store's flatness and relocatability (not in
Mokhov §3.1), the reverse-topological splice (not in the Acar paper), and "eager push"
(`lib/eager.nix` — RTD supplies the topological order, the eager characterisation is ours).

**What stays hedged is REACH, not provenance:** RTD's true `O(|AFFECTED|)` optimality and its
characteristic graphs are not reached in pure evaluation.

★ An earlier revision said RTD 1983 and Acar 2002 were "not in the archive". They are, in
`reference-catalog/` — a different tier from `used/`, and not the same claim.

- **Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte*** — the
  scheduler/rebuilder decomposition. This plane is the **rebuilder** dimension; the scheduler is
  Nix's own laziness, taken by the evaluator, so no scheduling belongs here. Named against the
  paper's own Table 2, the claimed cell is **suspending** scheduler (§4.1.3) × **verifying traces**
  (§4.2.2) — `verifyVT` is defined inside §4.2.2, so that is one coordinate and not two. This is
  deliberately *not* the paper's own Nix row, `nix = suspending dctRebuilder`, which is deep
  constructive traces (§4.2.4): §4.2.2 records that all traces except deep traces support early
  cutoff, and the cutoff is what the invalidation claim below needs. gen-rebuild's spike recorded
  §4.2.4 as an expected no-go, and that spike's finding travelled with the content. The verifying
  trace is realized here, in `lib/build.nix`.

  ★ **THE STORE'S FLATNESS AND RELOCATABILITY ARE NOT MOKHOV'S.** §3.1 defines the Store and states
  neither property; both are this library's own claim about its own store and are made in its own
  voice everywhere they appear. The attribution was inherited into this repository once already, from
  a source that made it in good faith, which is exactly why it is corrected in writing rather than
  quietly dropped.

- **Reps, Teitelbaum & Demers (1983)** — reverse-transitive-dependency propagation: the AFFECTED set
  (§4.3) and the unchanged-value cutoff (§4.1) supply the invalidation relation. True
  `O(|AFFECTED|)` optimality and characteristic graphs are recorded as **not reached** in pure
  evaluation; that hedge travelled with the content and is not re-opened by the move. VERIFIED at
  the primary: the paper states AFFECTED "is determined as a result of the updating process
  itself", which is why the cheap cone is an over-approximation and the exact set is post-filtered;
  `NeedToBeEvaluated` and the characteristic graphs are its own terms.

- **Acar (2002)** — the change/propagate split is the paper's two metafunctions, de-conflated here
  in `lib/drivers.nix` rather than fused. VERIFIED at the primary. ★ The *reverse-topological
  splice* is NOT: the paper carries no occurrence of the term, so that mechanism is this library's
  own and is attributed to no one.

- **Arntzenius (2016), Datafun** — reverse reachability, and the per-SCC least fixed point by
  iterate-from-bottom on finite-height semilattices (`lib/restabilize.nix`).

**The Mokhov memory claim is NARROWED, in writing.** A Mokhov rebuilder is *defined* by consulting
persistent build information — §3.1's store "also contains information maintained by the build
system itself, which persists from one invocation of the build system to the next — its 'memory'",
and §4.2.2 says the verifying trace *is* that memory. **A pure Nix evaluation has no
cross-invocation persistence.** That was carried here as an unsettled precondition; it is now
settled, and settled *against* the wide claim: **cross-build memory is NOT what is built.** The
plane's memory is the prior evaluation's own accessor, live inside the same evaluation, and its
scope is intra-evaluation reuse — the override cone, and reuse across the many targets composed
within one evaluation. The narrowing is recorded at the same change that fixes the interface,
because a claim stated up front cannot be quietly exchanged for a weaker one once code arrives, and
a narrowing discovered later by reading the code is exactly that exchange.

**What survives, and what does not.** Surviving: the verifying-trace *shape*, the
rebuilder/scheduler decomposition, and the reuse decision itself. Not surviving: persistence across
invocations, in any form. No part of this repository, and no library that takes its content, may
re-assert it.

**The growth path is NAMED, and it arrives owing an instrument.** Two shapes would restore
persistence — a materialised carrier the caller supplies as an ordinary input, and
import-from-derivation — and neither is built. Recording them is not a licence to take them: under
either, the PRIOR'S IDENTITY becomes an input, so a prior taken from a *different program* serves
wrong values however correct the cleanliness predicate is. No predicate the plane computes detects
that — the values are internally consistent and simply belong to another program — and the
byte-parity oracle does not cover it either, because it fixes the program across both runs and
*presumes* a matching prior. **A prior-provenance instrument is owed with the growth path, and
neither shape may be taken without one.** Restoring persistence would also not by itself restore
the Mokhov claim: a future revision that takes the growth path re-derives this paragraph rather than
deleting it. The matching limit on the RTD side arrived with the content and is carried forward here.

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
["affected","affectedSet","applyDelta","applyEdgeDelta","batch","build","dirtySet","earlyCutoff","force","forceCtx","impactOf","mkAccessor","needsEval","override","propagate","propagateEager","restabilize","retract","runScc","support","supportDirect","verify","why","whyNot"]
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
grep -rhoE '\btest-[A-Za-z0-9-]+' ci/tests/ | sort -u > /tmp/declared
nix-unit --flake ./ci#tests | grep -oE 'test-[A-Za-z0-9-]+' | sort -u > /tmp/collected
comm -23 /tmp/declared /tmp/collected   # declared but not collected — the silent-green case
comm -13 /tmp/declared /tmp/collected   # collected but not declared
```

Both are empty at this revision: 237 distinct names on each side, over a run of 239 cells (two names
recur across suites, which is why the reconciliation is on names and the run count is not the same
number).

★ THE CHARACTER CLASS IS `[A-Za-z0-9-]`, NOT `[a-z0-9-]`, and the difference is not cosmetic. Cell
names here contain capitals — `test-whyNot-…`, `test-affectedSet-…`, `test-hashEq-…` — and the
lower-case-only form truncates each at the capital, so it reports **212** names against the correct
**237**. A reconciliation run with it would show 25 spurious mismatches on one side and hide a real
one on the other.

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with
`working-directory: ci`):

```sh
nix flake check ./ci
```
