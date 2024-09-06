let lib = import "Contracts.ncl"
in
(
  lib.OneOf
    [
      Bool,
      Number,
    ]
)
