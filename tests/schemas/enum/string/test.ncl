let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    "red" | lib.IsContract contract,
    "green" | lib.IsContract contract,
    !("not-in-enum" | lib.IsContract contract),
  ]
