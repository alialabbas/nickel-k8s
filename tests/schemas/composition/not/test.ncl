let contract = import "contract.ncl" in
std.test.assert_all
  [
    (
      let val = {
        test = {
          regex = "test",
          test = "test",
        },
      }
      in (val | contract) == val
    )
  ]
