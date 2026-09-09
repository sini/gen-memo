# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-memo now has dependencies, so — per the gen root-file convention — this entry is a function
# of them rather than the lib value itself. The zero-input shape gen-prelude and gen-algebra ship
# was correct only while the plane was a shell. Defaults fetch the flake-locked revs
# (content-addressed via narHash, so the plain-import path stays pure and in lockstep with the
# flake output); pass either explicitly to override (e.g. a local gen-graph checkout).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ?
    name:
    builtins.fetchTree (
      let
        node = lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
      in
      node
    ),
  prelude ? import "${fetch "gen-prelude"}/lib",
  # Through gen-graph's OWN standalone entry rather than its `./lib`, so gen-graph's own
  # dependencies are satisfied from gen-graph's lock. Reaching for `./lib` obliged this file to
  # name that library's whole formal list by hand — a hand-picked list is a SECOND SIGNATURE that
  # nothing compares against the first. Through the entry, a formal gained downstream is defaulted
  # downstream and the divergence cannot form.
  graph ? import "${fetch "gen-graph"}" { inherit prelude; },
}:
import ./lib { inherit prelude graph; }
