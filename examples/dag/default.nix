# Standalone entrypoint: `nix eval -f examples/dag` → the demo record.
#
# Resolves gen-memo's lib from the repo's locked flake (getFlake reads the
# committed flake.lock). If your tree is dirty/uncommitted, run with --impure.
import ./demo.nix { genMemo = (builtins.getFlake (toString ../..)).lib; }
