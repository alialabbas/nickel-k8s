let contract = import "contract.ncl" in
std.test.assert_all
  [
    (let val = "valid" in (val | contract) == val)
  ]
