let contract = import "contract.ncl" in
std.test.assert_all
  [
    (
      let val = {
        ".hidden" = "hidden",
        rank = 1,
        name = "name",
      }
      in (val | contract) == val
    ),
    ({} | contract) == {},
  ]
