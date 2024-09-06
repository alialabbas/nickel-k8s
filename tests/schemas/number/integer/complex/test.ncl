let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    (21 | lib.IsContract contract),
    (25 | lib.IsContract contract),
    !(3 | lib.IsContract contract),
    !(30 | lib.IsContract contract),
  ]
