let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    1 | lib.contracts.IsContract contract,
    2 | lib.contracts.IsContract contract,
    !(5 | lib.contracts.IsContract contract),
  ]
