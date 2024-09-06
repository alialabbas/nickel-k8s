let contract = import "contract.ncl" in
let lib = import "Contracts.ncl" in
std.test.assert_all
  [
    10 | lib.IsContract contract,
    10.1 | lib.IsContract contract,
    true | lib.IsContract contract,
    !("true" | lib.IsContract contract),
  ]
