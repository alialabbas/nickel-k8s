let contract = import "contract.ncl" in
std.test.assert_all
  [
    ("test.yaml" | contract) == "test.yaml",
  ]
