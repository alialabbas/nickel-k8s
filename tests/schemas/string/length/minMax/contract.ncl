let lib = import "Contracts.ncl"
in
std.contract.all_of [ String, lib.Strings.MinLength 2, lib.Strings.MaxLength 5]