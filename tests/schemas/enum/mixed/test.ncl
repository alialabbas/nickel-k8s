let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    { first = 1 } | lib.contracts.IsContract contract,
    { string = "str" } | lib.contracts.IsContract contract,
    1 | lib.contracts.IsContract contract,
    true | lib.contracts.IsContract contract,
    !({ empty = "" } | lib.contracts.IsContract contract),
  ]
