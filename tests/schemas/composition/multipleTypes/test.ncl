let lib = import "lib.ncl" in
let contract = import "contract.ncl" in

std.test.assert_all
  [
    !("should not work" | lib.contracts.IsContract contract),
    "works" | lib.contracts.IsContract contract,

    1 | lib.contracts.IsContract contract,
    !(21 | lib.contracts.IsContract contract),

    !(true | lib.contracts.IsContract contract)
  ]
