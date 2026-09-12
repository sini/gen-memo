{
  description = "gen-memo — the incremental plane: a decision layer over the evaluator that never evaluates, only decides reuse";

  # Two inputs, and no more. gen-prelude supplies the nixpkgs-lib-free utility base; gen-graph
  # supplies the reverse reachability the dependent cone is READ from — the plane consumes that
  # traversal and never re-implements it. There is deliberately no evaluator input: the plane
  # decides for an evaluator it is handed, so taking one as a dependency would invert the
  # direction the whole design rests on. The content that landed here previously threaded an
  # evaluator argument that no operation consumed; it is not carried.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
  };

  # The test runner lives in ./ci, which is a separate flake.
  outputs =
    {
      gen-prelude,
      gen-graph,
      ...
    }:
    {
      # `nix flake check` forces the WHNF of every top-level output and nothing deeper, so this root's
      # green quantified over the `lib` SPINE alone: a member of the published surface could throw and
      # the check still exited 0 (measured — den-hoag-z1ta6). Hanging the force on that spine is what
      # makes the green mean "the surface evaluates", and a library needs no new output name for it.
      # The depth is each member's WHNF and no deeper: a retirement tombstone is a published `throw`
      # by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      lib =
        let
          surface = import ./lib {
            prelude = gen-prelude.lib;
            graph = gen-graph.lib;
          };
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
    };
}
