let lib = import "lib.ncl"
in
std.contract.all_of [ String, lib.strings.MinLength 2, lib.strings.MaxLength 5]
