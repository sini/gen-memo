# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-memo now has dependencies, so — per the gen root-file convention — this entry is a function
# of them rather than the lib value itself. The zero-input shape gen-prelude and gen-algebra ship
# was correct only while the plane was a shell.
{
  prelude,
  graph,
}:
import ./lib { inherit prelude graph; }
