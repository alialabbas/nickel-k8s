let lib = import "lib.ncl"
in
std.contract.all_of [std.number.Integer, lib.numbers.InRange 10 false 20 false ]
