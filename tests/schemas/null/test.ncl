let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    null | lib.contracts.IsContract contract
  ]
