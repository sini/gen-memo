# Purity invariant (gen-prelude design §5): gen-memo must import NO `nixpkgs.lib`. This pins
# "pure" as a checked property, not an aspiration — a stray `lib.foo` / `lib.types` /
# `evalModules` / nixpkgs input creeping into the library source fails CI.
#
# The plane decides reuse and never evaluates, so the module-system tokens below are the sharper
# half of the scan here: an `evalModules` or `mkOption` appearing in this library would be the
# plane doing the evaluator's work.
#
# Scope: lib/**.nix + the root flake.nix + default.nix (the library and its flake). NOT ci/ — the
# test harness legitimately uses nixpkgs.lib, including to run this scan.
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Comment-stripped source: drop everything from the first `#` on each line. Safe here because
  # `#` appears only in comments across these files (no `#` in string literals); documentation may
  # freely mention forbidden tokens without tripping the invariant.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  # Labels are repo-root-relative rather than bare basenames. `readDir libDir` yields
  # `default.nix` for `lib/default.nix`, which is the SAME string as the root `default.nix`
  # appended below — so an unqualified label makes a violation in the library indistinguishable
  # from one in the root entry, and the scan names a file that cannot be located.
  nixFiles = lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir));

  # ★ THE READ IS SPLIT, so the strip's premise can be asserted over the text the strip actually
  # received. One `readFile` per file feeds both lists, and `sources` is a TOTAL per-element
  # function of `rawSources` — `name` passes through, `code = stripComments text` — so pinning
  # `sources` pins `rawSources` up to the strip, and the premise arm below is asserted over the
  # same read as the cells that pin that subject. Two independent reads would make the composition
  # a hope rather than a construction.
  raw =
    entries:
    map (e: {
      inherit (e) name;
      text = builtins.readFile e.path;
    }) entries;

  # THE SUBJECT: the library tree plus its two roots. `reference/schedule.nix` is deliberately NOT
  # a member — it is the store-fix control's subject, not the library scan's, and joining it would
  # widen the library cell past `lib/**` plus the two roots and move both published label lists
  # (the manifest cell below carries that reasoning).
  #
  # What the exclusion costs, stated rather than glossed: that file is pinned by
  # `test-store-fix-scan-is-live` ALONE, which is weaker than the pair every cell here composes
  # with. A premise breach on the knot token's own line would red that cell for a reason a reader
  # would misdiagnose as the reference scheduler having lost the knot.
  rawSources =
    raw (
      map (name: {
        name = "lib/${name}";
        path = libDir + "/${name}";
      }) nixFiles
    )
    ++ [
      {
        name = "flake.nix";
        text = builtins.readFile ../../flake.nix;
      }
      {
        name = "default.nix";
        text = builtins.readFile ../../default.nix;
      }
    ];

  sources = map (s: {
    inherit (s) name;
    code = stripComments s.text;
  }) rawSources;

  # Tokens that signal a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  violations = lib.concatMap (
    src:
    map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
  ) sources;

  # Positive control for the scan itself: the same predicate, same run, over a string that DOES
  # contain a forbidden token. An empty `violations` above is only evidence if this is non-empty —
  # otherwise a broken `hasInfix` or an empty `sources` would report clean.
  controlViolations = lib.filter (
    tok: genPrelude.hasInfix tok "let x = evalModules { }; in x"
  ) forbidden;

  # THE PLANE BINDS NO STORE FIX, scanned over the same comment-stripped sources. A
  # self-referential store over the node set, passed into the caller's node computation, is what
  # makes a construct an evaluator rather than a decision layer — so the plane hands a domain, a
  # base and a decision to an engine and the engine binds the knot.
  #
  # ★ WHAT THIS TOKEN ARM CANNOT SEE, said here so its green is not read as wider than it is.
  # A store fix has other spellings, and the residue is FOUR sites, not the two an earlier form of
  # this comment named. A fold threading its own accumulator of resolved outputs across a traversal
  # it drives is the same construct by a different construction, and all four are in this library
  # (coordinates at the rev that added this cell):
  #
  #   1. `build.nix:155-190`        — the bottom-up condensation solve
  #   2. `restabilize.nix:134-139`  — `runScc`'s ascent, beneath the first
  #   3. `restabilize.nix:240-271`  — `restabilize`'s OWN cone solve, a separate fold from 2
  #   4. `eager.nix:71-75`          — the rank-ordered eager drain
  #
  # This scan is a tripwire against the knot coming back in the shape it left in, not a proof that
  # none is present.
  knotToken = "prelude.fix";
  knotSites = map (src: src.name) (lib.filter (src: genPrelude.hasInfix knotToken src.code) sources);

  # And its own live control: the SAME token and the SAME predicate over the reference scheduler,
  # which is where the knot now lives. Without this, a typo in the token would report the plane
  # clean of a construct the scan could never have matched.
  #
  # Asserted as the exact LABEL LIST, which is this file's idiom for every other control in it —
  # the forbidden-token control names its token, the import-route control names its seven files. A
  # truth value fails as `false != true` and names nothing; this names the file whose control
  # stopped firing, and a reader can open it. The subject is built through the same `raw` read as
  # the library subject, so the control and the scan cannot drift onto different reading machinery.
  #
  # ★ WHAT THE LABEL FORM DOES NOT BUY, measured rather than assumed, so the green is not read as
  # wider than it is. It catches the same mutations the truth value caught and reports them better:
  # a mistyped token and a read pointed at another file red either way. What neither form sees is a
  # read replaced by a constant carrying the token while this label is kept — that stays green here
  # exactly as it did before. The label is written beside the path rather than derived from it,
  # because deriving it would render a store path, which is what the label rule forbids.
  #
  # ★ THAT RESIDUE IS NOW CLOSED, by `test-store-fix-control-carries-its-file` below. This sentence
  # read "Pinning that residue needs a content axis for this subject, as the library subject has,
  # and this cell is not it." — the content axis exists now, and it is NOT shaped as the library
  # subject's: a proper subset of the MANIFEST is uninstantiable here, because this manifest is one
  # file and a singleton's only proper subset is empty. The axis is a declared token vocabulary
  # instead, and the paragraph on `knotControlVocab` states why.
  knotControlSources =
    map
      (s: {
        inherit (s) name;
        code = stripComments s.text;
      })
      (raw [
        {
          name = "reference/schedule.nix";
          path = ../../reference/schedule.nix;
        }
      ]);
  knotControlSites = map (s: s.name) (
    lib.filter (s: genPrelude.hasInfix knotToken s.code) knotControlSources
  );

  # THE CONTROL'S CONTENT AXIS (§4's C4b, n=1 case). The membership cell above names the file; this
  # names what the file CONTAINS, and without it the control has one axis where the only other
  # subject in this suite READ FROM DISK — the library tree — has two. Measured before it existed:
  # severing the read to a constant carrying the token, with the label kept, left `knotControlSites`
  # reading exactly its expectation — green over a subject that was no longer on disk.
  #
  # WHY A VOCABULARY AND NOT A LABEL SUBSET. C4b's content axis is a proper subset OF THE MANIFEST,
  # and this manifest is one file: the only proper subset of a singleton is empty, so the axis has no
  # instance over files here. It moves to a declared token vocabulary, where the proper-subset
  # property — and both of its directions — survive intact: a constant carrying less than the profile
  # collapses the list, one carrying more swells it past the subset. The four tokens below that the
  # file does NOT contain are what buy the swell direction; they are not padding.
  #
  # ★ `knotToken` IS THE FIRST ELEMENT BY CONSTRUCTION, never re-spelled. A mistyped token then reds
  # this cell and the membership cell together, instead of leaving this one green over a token the
  # other can no longer find.
  #
  # ★ THE SCAN IS BY LITERAL SUBSTRING, NOT BY PATTERN, and a future editor must keep it that way.
  # `genPrelude.hasInfix` escapes its needle (`escapeRegex`, nixpkgs' twelve metacharacters), so the
  # `.` in `prelude.fix` is a literal dot. Hand-rolling this with `builtins.split`/`match` on the raw
  # token instead would make it a wildcard: measured, unescaped `split "prelude.fix"` MATCHES
  # `preludeXfix`, while `hasInfix` does not.
  #
  # ★ WHAT THIS DOES NOT BUY, so its green is not read as wider than it is. It raises the cost of a
  # forged subject from one token to this whole profile; it does not make forgery impossible. A
  # constant reproducing all five carried tokens and none of the four absent still passes, as does a
  # duplicated pipeline pointed at a copy — the stated limit, unchanged.
  knotControlVocab = [
    knotToken
    "recompute"
    "isClean"
    "base // s"
    "prelude.genAttrs"
    "builtins.readFile"
    "import ./"
    "mkOption"
    "evalModules"
  ];
  knotControlCarried =
    let
      code = (builtins.head knotControlSources).code;
    in
    lib.filter (t: genPrelude.hasInfix t code) knotControlVocab;

  # ★ THE IMPORT ROUTE, which the token arm above does NOT close and which is the likelier way the
  # knot comes back. A `lib/` file that writes `import ../reference/schedule.nix` and calls
  # `schedule` itself has the knot back with no `prelude.fix` token anywhere in `lib/` — measured,
  # that plant leaves the token arm entirely green. Reaching the reference scheduler from inside
  # the plane is what would make it the plane's; being handed it at the call is what makes it the
  # caller's. So the path is scanned as well.
  importToken = "reference/";
  importSites = map (src: src.name) (
    lib.filter (src: genPrelude.hasInfix importToken src.code) sources
  );

  # Its live control is an import the library REALLY MAKES, so the predicate is shown to match an
  # import path in this corpus rather than merely to return empty. `./hash.nix` is imported
  # directly by the files that need the guards, which is the same syntactic shape a smuggled
  # `../reference/schedule.nix` would take.
  importControlSites = map (src: src.name) (
    lib.filter (src: genPrelude.hasInfix "./hash.nix" src.code) sources
  );

  # The token for the content half of the subject pinning below. Chosen because it is a PROPER
  # subset of the manifest and spans both branches of `sources`, which is what lets the cell
  # discriminate a constant-returning read in both directions.
  liveToken = "prelude";
  liveReads = map (s: s.name) (lib.filter (s: genPrelude.hasInfix liveToken s.code) sources);

  # ★ THE STRIP'S PREMISE, asserted rather than assumed. `stripComments` cuts each line at its
  # first `#`, which is sound only while no `#` in the scanned sources begins inside a string
  # literal. Where one does, the strip silently truncates LIVE CODE from that point to the end of
  # that line and the scanner goes blind there with no signal — per line, since the strip maps over
  # lines independently, so the damage is bounded and still unannounced.
  #
  # The predicate is LINE-LOCAL and conservative in the fail-safe direction: it counts quotes
  # before the first `#`, so a miscount over-reports and reds loudly rather than under-reporting
  # silently. It is deliberately NOT a string-aware tokenizer — that would be a larger unverified
  # instrument inside the oracle, needing its own premise-free proof, and its cheap form cannot see
  # a `''` block at all. That blind spot is declared as a surface instead, below.
  countQuotes = s: (lib.length (lib.splitString "\"" s)) - 1;
  firstHashInString =
    line:
    let
      parts = lib.splitString "#" line;
    in
    lib.length parts > 1 && lib.mod (countQuotes (lib.head parts)) 2 == 1;

  premiseBreaches = lib.concatMap (
    s:
    lib.concatMap (x: lib.optional (firstHashInString x.line) "${s.name}: ${toString x.n}") (
      lib.imap1 (n: line: { inherit n line; }) (lib.splitString "\n" s.text)
    )
  ) rawSources;

  # The predicate's own live control, over two literal lines written inside this cell: one carrying
  # a `#` inside a string, one an ordinary trailing comment. It proves the predicate FIRES and
  # discriminates; it says nothing about what the predicate was pointed at.
  premiseControlLines = [
    {
      name = "control: in-string hash";
      line = ''url = "https://example.com/x#frag";'';
    }
    {
      name = "control: ordinary comment";
      line = "  x = 1; # an ordinary trailing comment";
    }
  ];
  premiseControlHits = map (c: c.name) (lib.filter (c: firstHashInString c.line) premiseControlLines);

  # The declared surface: files where the line-local predicate is NOT conclusive, because a `''`
  # block can carry a `#` the quote parity above cannot see.
  multilineStringFiles = map (s: s.name) (lib.filter (s: genPrelude.hasInfix "''" s.text) rawSources);
in
{
  flake.tests.purity = {
    # This `[ ]` is not self-supporting: its subject is read from disk, so it is non-vacuous
    # exactly in composition with the subject-pinning pair asserted over the same `sources` value —
    # `test-scan-subject-is-the-library-tree` for WHICH files the scan reads, and
    # `test-scan-reads-are-live` for those files CARRYING THEIR TEXT. Neither alone: a scan of
    # nothing and a scan of constant text both report this clean.
    test-library-source-is-nixpkgs-lib-free = {
      expr = violations;
      expected = [ ];
    };

    # THE RESIDUAL CONTENT BOUND. This cell is kept for a residue the pair below cannot reach, not
    # because non-emptiness is evidence: the live-content list is a PROPER subset of the manifest by
    # construction, so `lib/affected.nix`, `lib/hash.nix` and `lib/strategies.nix` — the three files
    # that name no prelude — sit outside it. Emptying one of those three files' `code` ALONE leaves
    # the manifest green (the names are unchanged) and the live-content cell green (that label was
    # never in its list), and this is the only cell that reds it. Measured: `lib/hash.nix` code →
    # `""` alone reds this cell and nothing else.
    #
    # ★ WHAT IT IS NOT: a guarantee that the scan is non-vacuous. A cardinality predicate cannot see
    # an identity defect — a scan cut to half the library satisfies it with room to spare — and that
    # is `test-scan-subject-is-the-library-tree`'s job, not this cell's.
    test-scan-reads-non-empty-sources = {
      expr = sources != [ ] && lib.all (s: s.code != "") sources;
      expected = true;
    };

    # ★ THE SCAN'S SUBJECT, MEMBERSHIP HALF — the literal label list, asserted by identity rather
    # than by count. Disconnection is an identity defect and non-emptiness is a cardinality
    # predicate, so the two do not meet and the floor above cannot stand in for this: measured
    # against the suite WITHOUT this cell, `nixFiles` cut to just the seven labels the import-route
    # control names leaves every other cell here green while a live `lib.types` tether sits in one
    # of the seven files that left the scan. This cell is the one that reds that cut.
    #
    # It is ONE HALF of the pair every absence cell in this file composes with. An absence cell
    # asserts `expr == [ ]`, and a scan of nothing produces nothing — so this is what makes
    # `test-library-source-is-nixpkgs-lib-free`'s `[ ]`, `test-plane-binds-no-store-fix`'s `[ ]`
    # and `test-plane-does-not-import-the-reference-scheduler`'s `[ ]` evidence rather than
    # artefacts of an empty subject. Each of those is satisfied by a degenerate subject alone.
    #
    # WHAT IT IS SILENT ON: content. A `read` handing every entry one fixed string satisfies this
    # cell exactly — names are all it pins, and `test-scan-reads-are-live` below is what pins those.
    #
    # `reference/schedule.nix` is NOT a member, by construction rather than by omission: it is read
    # by the store-fix control below, which is a different subject, not by the library scan. It
    # carries a prelude, so joining it would move this list to 18 AND the live-content list to 14,
    # and widen the library cell's subject past `lib/**` plus the two roots, which is more than
    # that cell claims.
    test-scan-subject-is-the-library-tree = {
      expr = map (s: s.name) sources;
      expected = [
        "lib/affected.nix"
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/default.nix"
        "lib/dirtySet.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/hash.nix"
        "lib/merge.nix"
        "lib/provenance.nix"
        "lib/restabilize.nix"
        "lib/strategies.nix"
        "lib/structural.nix"
        "lib/warm.nix"
        "lib/warmTrace.nix"
        "flake.nix"
        "default.nix"
      ];
    };

    # ★ THE SCAN'S SUBJECT, CONTENT HALF — the labels above carry their files' text, asserted as
    # the exact list of sources that mention a prelude. The manifest cannot see this: a `read`
    # handing every entry one fixed string leaves the names untouched and satisfies it exactly.
    #
    # It is the OTHER HALF of the pair every absence cell here composes with. A constant-returning
    # read is invisible to `test-library-source-is-nixpkgs-lib-free`, to
    # `test-plane-binds-no-store-fix` and to `test-plane-does-not-import-the-reference-scheduler` —
    # each scans a subject with no forbidden token in it and reports clean — and this cell is what
    # makes it visible to them.
    #
    # THE LIST IS A PROPER SUBSET OF THE MANIFEST, and that is what gives it teeth in BOTH
    # directions. A constant carrying no prelude collapses this list toward empty; a constant
    # carrying one swells it to all seventeen. A list asserted at FULL coverage would be satisfied by
    # the second and would not discriminate it.
    #
    # `lib/affected.nix`, `lib/hash.nix`, `lib/strategies.nix` and `lib/warmTrace.nix` are outside
    # the list by construction, not by accident: `affected.nix` takes `{ graph, ... }`, `hash.nix`
    # takes `{ ... }` and reaches for `builtins.*` directly, `strategies.nix` takes `{ ... }` and
    # imports `./hash.nix`, and `warmTrace.nix` takes `{ ... }` and is two functions over data with
    # no traversal to fold. None names a prelude because none uses one. What bounds that residue is
    # `test-scan-reads-non-empty-sources` above: emptying one of those four files' `code` alone
    # leaves this cell green — the label was never in the list — and the floor is the only cell
    # that reds it.
    test-scan-reads-are-live = {
      expr = liveReads;
      expected = [
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/default.nix"
        "lib/dirtySet.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/merge.nix"
        "lib/provenance.nix"
        "lib/restabilize.nix"
        "lib/structural.nix"
        "lib/warm.nix"
        "flake.nix"
        "default.nix"
      ];
    };

    # THE PREMISE THE STRIP RELIES ON: no `#` in the scanned sources begins inside a string
    # literal. Asserted as the list of offending `file: line` coordinates, so a breach arrives as a
    # loud red a reader can open rather than as a silently shortened line.
    #
    # ★ WHAT THIS CELL DOES NOT DO, said here so its green is not read as wider than it is: it does
    # NOT red on a severed read. Its expectation is `[ ]`, and an emptied subject or one of constant
    # text satisfies it exactly — a scan of nothing breaches no premise. It is non-vacuous ONLY in
    # composition with `test-scan-subject-is-the-library-tree` and `test-scan-reads-are-live`,
    # asserted over the same `rawSources` read, which is what makes this `[ ]` a finding about real
    # text. The control below cannot supply that: its subject is a literal.
    test-strip-premise-holds = {
      expr = premiseBreaches;
      expected = [ ];
    };

    # The predicate fires, and discriminates. Its subject is two literal lines written inside this
    # cell, so it is UNSEVERABLE from the tree and therefore stands outside the composition rule
    # above — it neither needs a pair nor could honour one. It proves this predicate can match an
    # in-string `#` and does not match an ordinary comment; it says nothing whatever about what the
    # predicate was pointed at, and it is NOT the arming for the cell above.
    test-strip-premise-scan-is-live = {
      expr = premiseControlHits;
      expected = [ "control: in-string hash" ];
    };

    # The declared surface for the one blind spot the line-local predicate has: a `''` block can
    # carry a `#` that quote parity cannot see. The scanned files containing `''` are written down
    # rather than assumed away — empty here, so the FIRST arrival reds this cell and gets a reading,
    # exactly as a new library file arrives as a red on the manifest.
    test-strip-premise-multiline-strings = {
      expr = multilineStringFiles;
      expected = [ ];
    };

    test-forbidden-token-scan-is-live = {
      expr = controlViolations;
      expected = [ "evalModules" ];
    };

    test-plane-binds-no-store-fix = {
      expr = knotSites;
      expected = [ ];
    };

    test-store-fix-scan-is-live = {
      expr = knotControlSites;
      expected = [ "reference/schedule.nix" ];
    };

    # The content half of the store-fix CONTROL's own subject pinning (§4's C4, n=1 case): the
    # membership cell above pins WHICH file the control reads, this pins that the label carries its
    # file's text. NOT `test-plane-binds-no-store-fix`'s §4a pair — that is
    # `test-scan-subject-is-the-library-tree` + `test-scan-reads-are-live` over `sources`. This pair
    # arms the CONTROL, which is what makes that cell's token able to fire at all.
    # A proper subset of `knotControlVocab` — 5 of 9 — so a severed read reds it in both directions.
    test-store-fix-control-carries-its-file = {
      expr = knotControlCarried;
      expected = [
        "prelude.fix"
        "recompute"
        "isClean"
        "base // s"
        "prelude.genAttrs"
      ];
    };

    # The plane does not REACH the reference scheduler; it is handed one. Closing the import route
    # the token arm above leaves open.
    test-plane-does-not-import-the-reference-scheduler = {
      expr = importSites;
      expected = [ ];
    };

    # The import predicate matches a real import in this corpus, so the empty result above is a
    # finding rather than a predicate that could never have fired. Asserted as the exact file list
    # rather than as non-emptiness: a new direct importer of the guards should be seen, not absorbed.
    test-import-route-scan-is-live = {
      expr = importControlSites;
      expected = [
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/restabilize.nix"
        "lib/strategies.nix"
        "lib/structural.nix"
      ];
    };
  };
}
