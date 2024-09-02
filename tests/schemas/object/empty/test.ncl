let contract = import "contract.ncl" in
std.test.assert_all
  [
    (let val = { first = 1, string = "str", bool = true } in (val | contract) == val)
  ]
