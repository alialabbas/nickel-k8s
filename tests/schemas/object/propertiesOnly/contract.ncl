let lib = import "Contracts.ncl"
in
{
  string
    | String
    | optional,
  object
    | { .. }
    | optional,
  number
    | Number
    | optional,
  bool
    | Bool
    | optional,
  ..
}
