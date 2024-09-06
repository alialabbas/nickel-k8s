let lib = import "Contracts.ncl" in
let contract = import "contract.ncl" in
std.test.assert_all
  [
    (true | lib.IsContract contract),
    (false | lib.IsContract contract),
  ]
