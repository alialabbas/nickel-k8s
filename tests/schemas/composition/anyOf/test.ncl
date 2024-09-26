let contract = import "contract.ncl" in
let lib = import "lib.ncl" in
std.test.assert_all
  [
    10 | lib.contracts.IsContract contract,
    10.1 | lib.contracts.IsContract contract,
    true | lib.contracts.IsContract contract,
    !("true" | lib.contracts.IsContract contract),
  ]
