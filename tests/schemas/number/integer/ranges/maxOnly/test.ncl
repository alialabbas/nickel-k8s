let contract = import "contract.ncl" in
std.test.assert_all
  [
    (9 | contract) == 9,
    (-1 | contract) == -1,
    (-10 | contract) == -10
  ]
