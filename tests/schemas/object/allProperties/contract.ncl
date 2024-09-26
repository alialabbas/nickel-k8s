let lib = import "lib.ncl"
in
lib.records.JsonObject
  {
    rank = {
      contract = Number,
      optional = false
    },
  }
  {
    "^[.]" = String,
  }
  String
