let contract = import "contract.ncl" in
std.test.assert_all
  [
    (11 | contract) == 11,
    (19 | contract) == 19,
  ]
