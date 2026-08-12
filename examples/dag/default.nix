# Standalone entrypoint: `nix eval -f examples/dag` → the demo record.
#
# Resolves gen-memo's lib from the repo's locked flake (getFlake reads the
# committed flake.lock). If your tree is dirty/uncommitted, run with --impure.
#
# The engine comes from the same place, because the plane populates no store of its own: a
# caller with no evaluator to hand in brings the reference scheduler, which is what this
# standalone entry is.
let
  flake = builtins.getFlake (toString ../..);
in
import ./demo.nix {
  genMemo = flake.lib;
  engine = import ../../reference/schedule.nix {
    prelude = import "${flake.inputs.gen-prelude}/lib";
  };
}
