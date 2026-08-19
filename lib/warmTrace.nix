# warmTrace — an evaluator's own warm decision, OBSERVED, and the admission test that decides
# whether a warm pass may be asked for at all.
#
# THIS IS NOT `warmDecision`, AND THE NAMES DIFFER BECAUSE THE SUBJECTS DO. `warm.nix`'s
# `warmDecision` is what this plane CONSTITUTES — two total functions, `isClean` and `reusable`,
# over a declared node graph, and no values. Nothing here constitutes anything. Both functions
# below OBSERVE: one tests whether a caller's edit has the shape a warm pass may be asked for, the
# other narrows a decision some evaluator has already made and already published down to the
# fields a consumer reads. The plane decides the first record; it only watches the second.
#
# THE CALL DOES NOT CROSS, AND THAT IS WHY BOTH ARE FUNCTIONS OVER DATA. No evaluator is called
# here and none is named. Which argument key of a caller's re-composition carries reuse is a fact
# about that caller's own call surface, so it arrives as a parameter: a plane that decides for an
# evaluator it is HANDED — `warm.nix`'s direction rule — cannot hold that evaluator's argument
# names any more than it can hold its entry point.
#
# ★ THE OBSERVED RECORD'S FIELD NAMES ARE THE EVALUATOR'S, CARRIED VERBATIM, AND THAT IS A CHOICE
# RATHER THAN AN INHERITANCE. Restating an observation in this plane's vocabulary would make the
# plane appear to answer a question it did not answer, which is the confusion the name split above
# exists to prevent — so what is observed crosses as the observed party said it. These are not
# this substrate's words for anything; they are data, and a translation over them would be a
# second answer to a question that has one.
{ ... }:
{
  # WARM ADMISSION, SYNTACTIC OVER ARGUMENT KEYS. An edit is admissible for a warm pass exactly
  # when its key set is precisely `reuseKey` — the one argument whose change the evaluator's warm
  # splice is defined against. Every other argument of the caller's surface is then unchanged BY
  # CONSTRUCTION rather than by comparison, and that is the soundness argument the warm splice
  # needs: it reuses what the edit provably cannot have touched, and this test is the proof of
  # that premise.
  #
  # ★ THE TEST IS SYNTACTIC BECAUSE THE SEMANTIC ONE IS UNAVAILABLE, NOT BECAUSE IT IS CHEAPER —
  # and the scope of that word is exactly "an argument carrying a function", which is the ordinary
  # shape of a caller's non-edited arguments here. The semantic form is to compare the other
  # arguments and admit when they are equal; in Nix that comparison never reports two function
  # values equal, not even one binding against itself (measured at Nix 2.34.8:
  # `let f = x: x; in f == f` evaluates to `false`). A comparison that answers "changed" for an
  # argument nothing changed cannot witness "unchanged" for it, so there is no equality to fall
  # back on and the key set is the whole of the available evidence.
  #
  # THE REFUSAL IS SOFT, WHERE `warm.nix`'s `changesTopology` IS HARD, AND THE ASYMMETRY IS THE
  # POINT. Both refuse an edit rather than serve a decision whose premise the edit has broken. An
  # edge move is refused by throw because there is no correct answer to fall back to; a wider edit
  # is refused by `false` because there is one — an ordinary re-composition, which is what the
  # caller does when this returns false.
  warmAdmits = reuseKey: edits: builtins.attrNames edits == [ reuseKey ];

  # THE OBSERVED RECORD, WITH ITS ATTACHMENT RULE HELD AS A PROPERTY OF THE RECORD. A result
  # reached WITHOUT an edit has no decision to observe and carries no `trace`; a result reached
  # through one carries it, whichever way that decision went — a refused warm pass is an
  # observation too, and its `reason` is the whole of what a caller learns about the refusal. The
  # caller therefore splices this unconditionally, and the asymmetry lives here rather than in a
  # caller's branch where every new caller would restate it.
  #
  # THE NARROWING IS BY NAME, AND ITS FAILURE IS AT THE LOUD END OF THE RANGE. An evaluator whose
  # decision lacks one of the five aborts the evaluation NAMING that field, at the point a consumer
  # reads it — rather than publishing a defaulted value the consumer meets as a wrong answer. The
  # abort is stronger than a throw and that is worth stating exactly, because it is also why no
  # cell asserts it: measured at Nix 2.34.8, a missing-attribute error propagates THROUGH
  # `builtins.tryEval` while a `throw` in the same run is caught, so a cell over this case would
  # abort the suite instead of reddening in it.
  #
  # WHAT IS NOT NARROWED IS COST: every field is carried as a thunk and forced by nothing here.
  # That is load-bearing rather than incidental — at the evaluator this record's shape was migrated
  # from, two of the five enumerate the whole declared-loc partition when read, so an observation
  # that forced them would charge every consumer of the trace for a partition most of them never
  # look at.
  warmTrace =
    { edited, decision }:
    if edited then
      {
        trace = {
          inherit (decision)
            mode
            reason
            reused
            remerged
            modules
            ;
        };
      }
    else
      { };
}
