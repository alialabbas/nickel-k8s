let lib = import "lib.ncl"
in
{
  _ | (
    std.contract.all_of [
      {
        regex
          | doc "RE2 style regex-based match (https://github.com/google/re2/wiki/Syntax)."
          | String
          | optional,
        prefix
          | String
          | optional,
        exact
          | String
          | optional,
        ..
      },
      (
        lib.contracts.OneOf [
          (
            lib.records.JsonObject
              {
                regex = { contract = Dyn, optional = false, },
              }
              {}
              true
          ),
          (
            lib.records.JsonObject
              {
                prefix = { contract = Dyn, optional = false, },
              }
              {}
              true
          ),
          (
            lib.records.JsonObject
              {
                exact = { contract = Dyn, optional = false, },
              }
              {}
              true
          ),
          (
            std.contract.not (
              std.contract.any_of [
                (
                  lib.records.JsonObject
                    {
                      regex = { contract = Dyn, optional = false, },
                    }
                    {}
                    true
                ),
                (
                  lib.records.JsonObject
                    {
                      prefix = { contract = Dyn, optional = false, },
                    }
                    {}
                    true
                ),
                (
                  lib.records.JsonObject
                    {
                      exact = { contract = Dyn, optional = false, },
                    }
                    {}
                    true
                ),
              ]
            )
          ),
        ]
      )
    ]
  )
}
