let lib = import "Contracts.ncl"
in
lib.Records.JsonObject
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
