let lib = import "lib.ncl"
in
std.contract.from_predicate (fun val =>
  val == {
    string = "str",
    object = {
      number = 10,
      bool = true,
    },
    number = 1,
  }
)
