let contract = import "contract.ncl" in
std.test.assert_all
  [
    (5 | contract) == 5,
    (-15 | contract) == -15,
  ]
