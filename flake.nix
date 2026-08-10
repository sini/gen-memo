{
  description = "gen-memo — the incremental plane: a decision layer over the evaluator that never evaluates, only decides reuse";

  # NO inputs. gen-memo is a SHELL — the plane's content (the warm fold and override cone, the
  # dirty-cone propagation) is unwritten, so there is no dependency to declare yet. Declaring one
  # now would fix a layering the plane's own spec has not chosen, and the interface the plane reads
  # from the evaluator is exactly the part still to be designed. gen-prelude and gen-algebra ship
  # the same zero-input shape, so a consumer's lock gains nothing by taking this input.
  #
  # The test runner lives in ./ci, which is a separate flake.
  outputs =
    { ... }:
    {
      lib = import ./lib;
    };
}
