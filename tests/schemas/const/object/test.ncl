let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    { number = 1, string = "str", object = { bool = true, number = 10 } } | lib.IsContract contract,
    !({ number = -1, string = "not-match" } | lib.IsContract contract),
  ]
