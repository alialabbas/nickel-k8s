let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    true | lib.contracts.IsContract contract,
    !(false | lib.contracts.IsContract contract),
  ]
