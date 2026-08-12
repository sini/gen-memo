# gen-memo REPL — all exports in scope, plus the lib value itself as `genMemo`.
#
# `getFlake` on the repo root resolves the library's own locked inputs, so the REPL sees exactly
# what the flake output does rather than a hand-wired approximation of it.
let
  genMemo = (builtins.getFlake (toString ../.)).lib;
in
{
  inherit genMemo;
}
// genMemo
