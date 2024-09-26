let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    { number = 1, string = "str", object = { bool = true, number = 10 } } | lib.contracts.IsContract contract,
    !({ number = -1, string = "not-match" } | lib.contracts.IsContract contract),
  ]
