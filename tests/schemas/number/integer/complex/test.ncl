let lib = import "lib.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    (21 | lib.contracts.IsContract contract),
    (25 | lib.contracts.IsContract contract),
    !(3 | lib.contracts.IsContract contract),
    !(30 | lib.contracts.IsContract contract),
  ]
