# gen-memo REPL — all exports in scope, plus the lib value itself as `genMemo`.
#
# The shell exports nothing yet, so the splice contributes no bindings and `genMemo` is `{ }`;
# both stay correct as the surface fills in.
let
  genMemo = import ../lib;
in
{
  inherit genMemo;
}
// genMemo
