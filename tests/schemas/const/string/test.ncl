let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    "test" | lib.contracts.IsContract contract,
    !("not-matching" | lib.contracts.IsContract contract),
  ]
