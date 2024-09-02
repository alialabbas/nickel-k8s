let lib = import "Contracts.ncl"
in
std.contract.all_of [std.number.Integer, lib.Numbers.InRange 10 false 20 false ]
