let contract = import "contract.ncl" in
std.test.assert_all
  [
    (1 | contract) == 1,
    (-1 | contract) == -1,
  ]
