let generator = import "schema.ncl" in

{
  Input | { .. },
  Output =
    "let lib = import \"lib.ncl\" \n in \n"
    ++ generator.json_schema_to_nickel
      Input
      false,
}
