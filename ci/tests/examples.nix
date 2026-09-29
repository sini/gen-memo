{ genMemo, engine, ... }:
{
  gen.ci.examples.dag = import ../../examples/dag/demo.nix { inherit genMemo engine; };
}
