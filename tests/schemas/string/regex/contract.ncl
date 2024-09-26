let lib = import "lib.ncl"
in
std.contract.all_of [ String, lib.strings.Regex "^[a-zA-Z]+\\.yaml"]
