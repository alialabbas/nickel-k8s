let lib = import "lib.ncl"
in
lib.enum.ArrayEnum [
  true,
  1,
  {
    string = "str",
  },
  {
    first = 1,
  },
]
