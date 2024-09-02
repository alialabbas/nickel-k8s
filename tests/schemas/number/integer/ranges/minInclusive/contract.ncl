let lib = import "Contracts.ncl"
in
std.contract.all_of [ Number, lib.Numbers.InRange 0 false 100 false ]
