# merge — the module fold that REFUSES a collision instead of resolving it by position.
#
# A plain `//` fold makes the export surface a function of list order: two modules defining one
# name leaves the later one reachable and the earlier one dead, with nothing to read that says
# so. The content this library received shipped exactly that — a fused definition silently
# shadowing a whole file — and the shadow was found by probing a returned record for a key only
# one of the two adds, which is not a thing a reader does. Refusing names the colliding pair at
# evaluation time instead, so the order of a module list cannot decide which definition ships.
#
# Separate from `default.nix` so the refusal is testable against a pair that actually collides:
# a rule that only ever runs over modules known not to collide is a rule whose firing has never
# been observed, and an empty collision list proves nothing about it.
#
# NOT part of the public surface — `default.nix` does not fold this file in.
{ prelude, ... }:
{
  mergeExports =
    label: acc: new:
    let
      collisions = prelude.filter (n: acc ? ${n}) (builtins.attrNames new);
    in
    if collisions == [ ] then
      acc // new
    else
      throw "gen-memo: duplicate export from ${label}: ${builtins.toJSON collisions}";
}
