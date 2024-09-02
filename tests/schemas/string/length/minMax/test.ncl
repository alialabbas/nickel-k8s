let contract = import "contract.ncl" in
std.test.assert_all
  [
    ("test" | contract) == "test",
  ]
