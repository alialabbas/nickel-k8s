let lib = import "Contracts.ncl" in
{ test = 1, r = { test = 1 } } | lib.Records.IsRecord { test = Number, r = { test = String } }
