let lib = import "Contracts.ncl"
in
std.contract.all_of [ String, lib.Strings.Regex "^[a-zA-Z]+\\.yaml"]
