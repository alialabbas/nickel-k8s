let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    1 | lib.IsContract contract,
    !(2 | lib.IsContract contract),
  ]
