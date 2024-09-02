let lib = import "Contracts.ncl"
in
std.contract.all_of [ String, lib.Strings.MaxLength 4]
