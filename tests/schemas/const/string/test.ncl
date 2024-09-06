let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    "test" | lib.IsContract contract,
    !("not-matching" | lib.IsContract contract),
  ]
