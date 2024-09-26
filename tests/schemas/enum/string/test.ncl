let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    "red" | lib.contracts.IsContract contract,
    "green" | lib.contracts.IsContract contract,
    !("not-in-enum" | lib.contracts.IsContract contract),
  ]
