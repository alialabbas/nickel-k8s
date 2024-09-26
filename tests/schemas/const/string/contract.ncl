let lib = import "lib.ncl"
in
std.contract.from_predicate (fun val => val == "test")
