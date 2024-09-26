let lib = import "lib.ncl"
in
(
  std.contract.all_of [
    std.contract.all_of [ Number, lib.numbers.MultipleOf 5],
    Number,
  ]
)
