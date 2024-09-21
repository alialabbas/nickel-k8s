let lib = import "Contracts.ncl"
in
lib.Enum.ArrayEnum [
  true,
  1,
  {
    string = "str",
  },
  {
    first = 1,
  },
]
