let lib = import "lib.ncl"
in
std.contract.all_of [ Number, lib.numbers.InRange 0 false 100 false ]
