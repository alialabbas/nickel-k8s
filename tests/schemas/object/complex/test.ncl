let contract = import "contract.ncl" in
let val = { test = { test = "test", }, } in (val | contract)
