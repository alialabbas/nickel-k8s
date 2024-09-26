let lib = import "lib.ncl"
in
std.contract.all_of [std.number.Integer, lib.numbers.MinRange 0 false ]
