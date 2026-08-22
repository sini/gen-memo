# I9 — THE CTX FIELD SET, ENUMERATED AT THE CONSUMER.
#
# The plane is handed a `ctx` assembled by its caller. Nothing types that record, so a field the
# plane starts reading, or stops reading, moves the interface with no signal: the caller learns of
# it as a missing-attribute error surfacing deep inside a fold, at whichever node happened to be
# forced first. This suite publishes the field set the plane REQUIRES, as data, and asserts it
# against what `../../lib` actually reads.
#
# ★ WHY THE CONSUMER AND NOT THE ASSEMBLY SITE. The scope↔plane interface spec sites this oracle
# here deliberately (its I9 row, gate P10). The assembly site today is in `gen-resolve`, the only
# repository referencing `foldEquations`, and that library is being retired — an oracle whose only
# home is a construct marked for retirement fails the same "does its subject survive?" predicate
# every other cell here is held to. The plane is the STABLE end of this interface, and it is the
# side whose reads DEFINE the requirement, so the enumeration belongs where the reads are.
#
# ★ WHAT THAT COSTS, STATED SO THE GREEN IS NOT READ AS WIDER THAN IT IS. This suite checks the
# plane's DEMAND, not the caller's SUPPLY. A caller that omits a required field still fails at
# evaluation rather than at a cell; closing that half needs a constructor at whatever succeeds
# gen-resolve as the caller, and no such successor exists yet. The residual is recorded here rather
# than assigned to a library that does not exist.
#
# ★★★ THE PREDICATE COVERS BOTH READ FORMS, AND THAT IS THE WHOLE INSTRUMENT. Nix spells an
# attribute read two ways, and a scan that sees only `ctx.<field>` is not slightly incomplete — it
# is wrong by exactly the fields that happen to be spelled the other way. Measured here: the dot
# form alone finds NINE of the eleven, missing `attributes` and `parseParent`, both of which reach
# the plane only through `inherit (ctx) …` at `lib/warm.nix:133`. That two-short count is not
# hypothetical — it is the count the interface spec's own gate produced before the second form was
# added, reproduced below as a live control rather than described in a comment.
{
  lib,
  ...
}:
let
  libDir = ../../lib;

  # Comment-stripped source, the same strip `purity.nix` uses and on the same premise: `#` appears
  # in these files only in comments. That premise is ASSERTED, not assumed — `purity.nix`'s
  # `test-strip-premise-holds` scans `lib/**` plus the two roots, a strict superset of this
  # subject, so it is pinned there rather than re-implemented here. A comment mentioning `ctx.foo`
  # must not be counted as a read.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  nixFiles = lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir));
  sources = map (name: {
    name = "lib/${name}";
    code = stripComments (builtins.readFile (libDir + "/${name}"));
  }) nixFiles;

  # ---- FORM 1 · `ctx.<field>` (and the primed binding `ctx'.<field>`) --------------------------
  #
  # The leading `(^|[^a-zA-Z0-9_'-])` is a hand-written left word boundary and it is load-bearing:
  # without it the pattern matches the tail of any identifier ENDING in `ctx`, so a hypothetical
  # `warmCtx.store` would be reported as a `ctx` field. Measured at this revision: no such
  # identifier exists in `lib/`, which means the guard cannot be validated by the corpus and is
  # kept because the corpus is what would change.
  dotFields =
    code:
    let
      parts = builtins.split "(^|[^a-zA-Z0-9_'-])ctx'?\\.([a-zA-Z_][a-zA-Z0-9_'-]*)" code;
    in
    map (m: builtins.elemAt m 1) (builtins.filter builtins.isList parts);

  # ---- FORM 2 · `inherit (ctx) a b c;` --------------------------------------------------------
  #
  # The block may span lines (`lib/drivers.nix:112` spans five), so the segment following each
  # match is taken up to its first `;` and split on whitespace. Splitting on the LITERAL `;` is
  # what bounds the read: without it, every identifier after the last inherit block to the end of
  # file would be collected.
  inheritFields =
    code:
    let
      parts = builtins.split "inherit[[:space:]]+\\(ctx'?\\)" code;
      indexed = lib.imap0 (i: p: { inherit i p; }) parts;
      # The string segment immediately following a match — i.e. whose predecessor is a match list.
      afterMatch = builtins.filter (
        e: !(builtins.isList e.p) && e.i > 0 && builtins.isList (builtins.elemAt parts (e.i - 1))
      ) indexed;
      idsOf =
        seg:
        builtins.filter (t: t != "" && builtins.match "[a-zA-Z_][a-zA-Z0-9_'-]*" t != null) (
          lib.splitString " " (
            builtins.replaceStrings [ "\n" "\t" ] [ " " " " ] (lib.head (lib.splitString ";" seg))
          )
        );
    in
    builtins.concatMap (e: idsOf e.p) afterMatch;

  srt = lib.sort builtins.lessThan;
  dotOnly = lib.unique (builtins.concatMap (s: dotFields s.code) sources);
  inheritOnly = lib.unique (builtins.concatMap (s: inheritFields s.code) sources);

  # THE MEASURED SET: the union of both forms, which is what the plane requires.
  required = srt (lib.unique (dotOnly ++ inheritOnly));

  # ---- The predicate's own live subject, for the seeded-defect controls ------------------------
  #
  # A literal source carrying a TWELFTH field in each form. Its subject is written inside this file
  # and is therefore unseverable from the tree: it proves the extractors CAN fire on a new field,
  # and says nothing about what they were pointed at. That second half is the manifest cell's job.
  seededSource = ''
    let
      a = ctx.twelfthField;
      b = ctx'.primedField;
    in
    {
      inherit (ctx)
        thirteenthField
        fourteenthField
        ;
      unrelated = other.notAField;
    }
  '';
in
{
  flake.tests."ctx-fields" = {
    # ★★★ THE ORACLE. The eleven fields the plane reads, asserted by identity.
    #
    # This cell is SELF-ARMING against a severed subject in a way the absence cells in `purity.nix`
    # are not: its expectation is a non-empty exact list, so a scan of nothing, or of constant
    # text, collapses `required` to `[ ]` and reds it. That is why it carries no separate
    # non-emptiness floor.
    #
    # A field ADDED to the plane's reads reds this cell with the new name in the diff; a field
    # DROPPED reds it with the name missing. Either way the interface moves loudly.
    test-ctx-field-set-is-the-published-eleven = {
      expr = required;
      expected = [
        "accessor"
        "attributes"
        "eval"
        "fixpoint"
        "hashOf"
        "parseParent"
        "pending"
        "recompute"
        "roots"
        "store"
        "trace"
      ];
    };

    # ★★★ THE INSTRUMENT LESSON, AS A CELL RATHER THAN A COMMENT. The dot form alone finds nine of
    # the eleven. This is the exact defect the interface spec's gate hit — its count came out two
    # short — and it is reproduced here so that a future editor who "simplifies" the extractor down
    # to one form reds THIS cell and reads why, instead of silently narrowing the oracle.
    #
    # It is asserted as the exact nine rather than as a count: a count of nine is also satisfied by
    # a scan that found nine DIFFERENT names.
    test-control-dot-form-alone-is-two-short = {
      expr = srt dotOnly;
      expected = [
        "accessor"
        "eval"
        "fixpoint"
        "hashOf"
        "pending"
        "recompute"
        "roots"
        "store"
        "trace"
      ];
    };

    # The other half of the same pair: the two fields reachable ONLY through `inherit (ctx) …`.
    # Without this the cell above could be satisfied by a union that happened to equal the dot set.
    test-control-inherit-form-carries-the-missing-two = {
      expr = srt (lib.subtractLists dotOnly inheritOnly);
      expected = [
        "attributes"
        "parseParent"
      ];
    };

    # THE SEEDED DEFECT — a twelfth field silently required — shown DETECTED, in both forms, in the
    # same run the oracle above passes clean. Without this, a broken extractor returning `[ ]` for
    # every input would leave the oracle red rather than green, but a extractor broken in the OTHER
    # direction — one that matched nothing new — would be invisible.
    test-control-extractor-sees-a-seeded-twelfth-field = {
      expr = srt (lib.unique (dotFields seededSource ++ inheritFields seededSource));
      expected = [
        "fourteenthField"
        "primedField"
        "thirteenthField"
        "twelfthField"
      ];
    };

    # ★ THE SEGMENT BOUND, armed. `inherit (ctx) …` collection stops at the first `;`. The seeded
    # source above carries `other.notAField` AFTER the inherit block's semicolon; its absence from
    # the list above is what proves the bound holds, and this cell names the mechanism so that
    # absence is read as a finding rather than as a coincidence of the fixture.
    test-control-inherit-collection-stops-at-the-semicolon = {
      expr = builtins.elem "unrelated" (inheritFields seededSource);
      expected = false;
    };

    # ★ THE SCAN'S SUBJECT, membership half — which files were read, by identity. The oracle cell
    # reds on an emptied subject, but it cannot distinguish a scan of the whole library from a scan
    # of the six files that happen to carry all eleven names between them. This cell is what reds
    # that narrowing, and it is where a new library file arrives.
    test-ctx-scan-subject-is-the-library-tree = {
      expr = map (s: s.name) sources;
      expected = [
        "lib/affected.nix"
        "lib/affectedSet.nix"
        "lib/build.nix"
        "lib/default.nix"
        "lib/dirtySet.nix"
        "lib/drivers.nix"
        "lib/eager.nix"
        "lib/graph-view.nix"
        "lib/hash.nix"
        "lib/merge.nix"
        "lib/provenance.nix"
        "lib/restabilize.nix"
        "lib/strategies.nix"
        "lib/structural.nix"
        "lib/warm.nix"
        "lib/warmTrace.nix"
      ];
    };
  };
}
