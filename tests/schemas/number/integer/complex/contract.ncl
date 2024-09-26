let lib = import "lib.ncl"
in
(
  std.contract.all_of [
    std.contract.all_of [std.number.Integer, lib.numbers.MinRange 20 false ],
    (
      lib.contracts.OneOf [
        std.contract.all_of [std.number.Integer, lib.numbers.MultipleOf 5],
        std.contract.all_of [std.number.Integer, lib.numbers.MultipleOf 3],
      ]
    )
  ]
)
