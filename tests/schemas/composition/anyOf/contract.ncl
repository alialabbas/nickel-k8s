let lib = import "lib.ncl"
in
(
  std.contract.any_of [
    Bool,
    Number,
  ]
)
