let lib = import "lib.ncl"
in
lib.contracts.OneOf [
  std.contract.all_of [std.number.Integer, lib.numbers.MaxRange 20 false ],
  std.contract.all_of [ String, lib.strings.MaxLength 10],
]
