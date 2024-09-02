let contract = import "contract.ncl" in
std.test.assert_all
  [
    (let val = { test = "working" } in (val | contract) == val),
  ]
