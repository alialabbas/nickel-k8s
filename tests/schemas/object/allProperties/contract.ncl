let lib = import "Contracts.ncl"
in
lib.Records.JsonObject
  {
    rank
      | Number
      | optional,
    ..
  }
  {
    "^[.]" = String,
  }
  String
