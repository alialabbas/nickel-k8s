let lib = import "Contracts.ncl"
in
(
  std.contract.any_of
    [
      Bool,
      Number,
    ]
)
