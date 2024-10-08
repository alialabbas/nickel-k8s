let lib = import "lib.ncl"
in
{
  string
    | String
    | optional,
  object
    | {
      ..
    }
    | optional,
  number
    | Number
    | optional,
  bool
    | Bool
    | optional,
  ..
}
