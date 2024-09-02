let lib = import "Contracts.ncl"
in
lib.Records.JsonObject
  {
    ..
  }
  {}
  (std.contract.all_of
  [
    (
      lib.OneOf
        [
          {
            regex | Dyn,
            ..
          },
          {
            prefix | Dyn,
            ..
          },
          {
            exact | Dyn,
            ..
          },
          std.contract.not
            (
              std.contract.any_of
                [
                  {
                    regex | Dyn,
                    ..
                  },
                  {
                    prefix | Dyn,
                    ..
                  },
                  {
                    exact | Dyn,
                    ..
                  },
                ]
            ),
        ]
    ),
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
    }
  ])
