let lib = import "Contracts.ncl"
in
(
  std.contract.all_of
    [
      std.contract.all_of [std.number.Integer, lib.Numbers.MinRange 20 false ],
      (
        lib.OneOf
          [
            std.contract.all_of [std.number.Integer, lib.Numbers.MultipleOf 5],
            std.contract.all_of [std.number.Integer, lib.Numbers.MultipleOf 3],
          ]
      )
    ]
)
