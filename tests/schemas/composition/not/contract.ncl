let lib = import "Contracts.ncl"
in
{
  _ | (
    std.contract.all_of [
      {
        regex
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
        lib.OneOf [
          lib.Records.JsonObject
            {
              regex = { contract = Dyn, optional = false, },
            }
            {}
            true,
          lib.Records.JsonObject
            {
              prefix = { contract = Dyn, optional = false, },
            }
            {}
            true,
          lib.Records.JsonObject
            {
              exact = { contract = Dyn, optional = false, },
            }
            {}
            true,
          (
            std.contract.not (
              std.contract.any_of [
                lib.Records.JsonObject
                  {
                    regex = { contract = Dyn, optional = false, },
                  }
                  {}
                  true,
                lib.Records.JsonObject
                  {
                    prefix = { contract = Dyn, optional = false, },
                  }
                  {}
                  true,
                lib.Records.JsonObject
                  {
                    exact = { contract = Dyn, optional = false, },
                  }
                  {}
                  true,
              ]
            )
          ),
        ]
      )
    ]
  )
}
