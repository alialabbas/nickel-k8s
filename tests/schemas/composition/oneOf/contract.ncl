let lib = import "lib.ncl"
in
(
  lib.contracts.OneOf [
    Bool,
    Number,
  ]
)
