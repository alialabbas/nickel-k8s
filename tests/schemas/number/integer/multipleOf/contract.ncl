let lib = import "lib.ncl"
in
std.contract.all_of [std.number.Integer, lib.numbers.MultipleOf 5]
