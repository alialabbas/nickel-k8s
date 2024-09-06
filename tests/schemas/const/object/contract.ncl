let lib = import "Contracts.ncl"
in
std.contract.from_predicate
  (
    fun val =>
      val == {
        string = "str",
        object = {
          number = 10,
          bool = true,
        },
        number = 1,
      }
  )
