let schema = import "schema.json" in
let generator = import "schema.ncl" in
"let lib = import \"Contracts.ncl\" \n in \n"
++ generator.SchemaToNickel
  schema
