let lib = import "lib.ncl"
in
lib.records.JsonObject
  {
    rank = {
      contract = Number,
      optional = true
    },
  }
  {
    "^[.]" = String,
  }
  String
