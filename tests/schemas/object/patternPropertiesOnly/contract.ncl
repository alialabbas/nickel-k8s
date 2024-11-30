let lib = import "lib.ncl"
in
(
  lib.records.JsonObject
    {}
    {
      "^[.]" = String,
    }
    true
)
