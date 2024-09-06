let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    { first = 1 } | lib.IsContract contract,
    { string = "str" } | lib.IsContract contract,
    !({ empty = "" } | lib.IsContract contract),
  ]
