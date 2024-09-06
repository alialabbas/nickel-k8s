let lib = import "Contracts.ncl"
in
(
  std.contract.all_of
    [
      std.contract.all_of [ Number, lib.Numbers.MultipleOf 5],
      Number,
    ]
)
