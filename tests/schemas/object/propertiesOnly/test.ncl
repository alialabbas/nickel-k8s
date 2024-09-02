let contract = import "contract.ncl" in
std.test.assert_all
  [
    (let val = {} in (val | contract) == val),
    (
      let val = {
        number = 1,
        string = "str",
        bool = true,
        object = {
          anything = "goes-here",
        }
      }
      in (val | contract) == val
    ),
    (let val = { unchecked = "should-work", } in (val | contract) == val)
  ]
