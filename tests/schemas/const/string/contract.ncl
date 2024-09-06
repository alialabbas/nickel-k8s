let lib = import "Contracts.ncl"
in
std.contract.from_predicate (fun val => val == "test")
