let lib = import "../Contracts.ncl" in
let oneOfTests = [
  1 | lib.IsContract (lib.OneOf [ Number, String, Bool ]),
  "string" | lib.IsContract (lib.OneOf [ Number, String, Bool ]),
  true | lib.IsContract (lib.OneOf [ Number, String, Bool ]),
  !("STR" | lib.IsContract (lib.OneOf [ String, String, Bool ])),
]
in
let stringTests = [
  "str" | lib.IsContract (lib.Strings.MinLength 1),
  !("str" | lib.IsContract (lib.Strings.MinLength 4)),
  "str" | lib.IsContract (lib.Strings.MaxLength 5),
  !("strstr" | lib.IsContract (lib.Strings.MaxLength 5)),
  "test.yaml" | lib.IsContract (lib.Strings.Regex "^[a-zA-Z]+\\.ya?ml$"),
  !("1234" | lib.IsContract (lib.Strings.Regex "^[a-zA-Z]+$")),
]
in
let numberTests = [
  1 | lib.IsContract (lib.Numbers.Percentage),
  "23%" | lib.IsContract (lib.Numbers.Percentage),
  !("invalid" | lib.IsContract (lib.Numbers.Percentage)),
  10 | lib.IsContract (lib.Numbers.MinRange 10 true),
  !(10 | lib.IsContract (lib.Numbers.MinRange 10 false)),
  100 | lib.IsContract (lib.Numbers.MinRange 100 true),
  !(100 | lib.IsContract (lib.Numbers.MinRange 100 false)),
  100 | lib.IsContract (lib.Numbers.MultipleOf 10),
  !(15 | lib.IsContract (lib.Numbers.MultipleOf 4)),
]
in
let arraysTests = [
  [1, 2, 3] | lib.IsContract (lib.Arrays.IsSet),
  !([1, 2, 2, 3, 2, 1] | lib.IsContract (lib.Arrays.IsSet)),
  [1, 2, 3] | lib.IsContract (lib.Arrays.Length { min = 2 }),
  [1, 2, 3] | lib.IsContract (lib.Arrays.Length { min = 1, max = 3 }),
  !([1, 2, 3] | lib.IsContract (lib.Arrays.Length { min = 4, max = 5 })),
  [1, 2, 3, "1"] | lib.IsContract (lib.Arrays.Contains { min = 1, } String),
  !([1, 2, 3, ] | lib.IsContract (lib.Arrays.Contains { min = 1, } String)),
  [1, 2, 3, ] | lib.IsContract (lib.Arrays.Length { min = 1, max = 3 }),
  !([] | lib.IsContract (lib.Arrays.Length { min = 1, max = 3 })),
  !([1, 2, 3, 4, 5] | lib.IsContract (lib.Arrays.Length { min = 1, max = 3 })),
  ["first", "second", ] | lib.IsContract (lib.Arrays.Tuple [ String, String, Number ] 'Exact),
  ["first", "second", 1] | lib.IsContract (lib.Arrays.Tuple [ String, String, Number ] 'Exact),
  # ["first", "second", 1] | lib.IsContract (lib.Arrays.Tuple [ String, String, Number ] 'AdditionalItems String)
]
in
let formatsTests = [
  "639addf5-9297-4749-ae1e-ac1f9de1cbf3" | lib.IsContract lib.UUID,
  !("639addf592974749ae1eac1f9de1cbf3" | lib.IsContract lib.UUID),
  !("639addf5-9297-4749-ae1e-ac1f9de1c3" | lib.IsContract lib.UUID),
]
in
let recordTests = [
  let val = { a = "test" } in
  (
    val
      | lib.Records.JsonObject
        {
          a = { optional = false, contract = String },
          b = { optional = true, contract = Number }
        }
        {}
        false
  ) == val,
  (
    { a = { b = 1, c = "3" } }
      | lib.Records.JsonObject
        {
          a = {
            optional = false,
            contract = (
              lib.Records.JsonObject
                {
                  b = { optional = false, contract = Number, },
                  c = {
                    optional = false,
                    contract = String
                  }
                }
                {}
                false
            )
          },
        }
        {}
        false
  ) == { a = { b = 1, c = "3" } },
]
in
std.test.assert_all
  (
    oneOfTests
    @ stringTests
    @ numberTests
    @ arraysTests
    @ formatsTests
    @ recordTests
  )
