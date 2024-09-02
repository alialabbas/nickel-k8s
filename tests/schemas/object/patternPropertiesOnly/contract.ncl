let lib = import "Contracts.ncl"
in
lib.Records.JsonObject
  {
    ..
  }
  {
    "^[.]" = String,
  }
  true
