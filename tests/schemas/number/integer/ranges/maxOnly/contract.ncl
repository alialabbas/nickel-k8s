let lib = import "Contracts.ncl"
in
std.contract.all_of [std.number.Integer, lib.Numbers.MaxRange 10 false ]
