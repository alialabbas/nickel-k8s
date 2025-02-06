let lib = import "../lib.ncl" in
let oneOfTests = [
  1 | lib.contracts.IsContract (lib.contracts.OneOf [ Number, String, Bool ]),
  "string" | lib.contracts.IsContract (lib.contracts.OneOf [ Number, String, Bool ]),
  true | lib.contracts.IsContract (lib.contracts.OneOf [ Number, String, Bool ]),
  !("STR" | lib.contracts.IsContract (lib.contracts.OneOf [ String, String, Bool ])),
]
in
let stringTests = [
  "str" | lib.contracts.IsContract (lib.strings.MinLength 1),
  !("str" | lib.contracts.IsContract (lib.strings.MinLength 4)),
  "str" | lib.contracts.IsContract (lib.strings.MaxLength 5),
  !("strstr" | lib.contracts.IsContract (lib.strings.MaxLength 5)),
  "test.yaml" | lib.contracts.IsContract (lib.strings.Regex "^[a-zA-Z]+\\.ya?ml$"),
  !("1234" | lib.contracts.IsContract (lib.strings.Regex "^[a-zA-Z]+$")),
]
in
let numberTests = [
  1 | lib.contracts.IsContract (lib.numbers.NumberOrPercentage),
  "23%" | lib.contracts.IsContract (lib.numbers.NumberOrPercentage),
  !("invalid" | lib.contracts.IsContract (lib.numbers.NumberOrPercentage)),
  10 | lib.contracts.IsContract (lib.numbers.MinRange 10 true),
  !(10 | lib.contracts.IsContract (lib.numbers.MinRange 10 false)),
  100 | lib.contracts.IsContract (lib.numbers.MinRange 100 true),
  !(100 | lib.contracts.IsContract (lib.numbers.MinRange 100 false)),
  100 | lib.contracts.IsContract (lib.numbers.MultipleOf 10),
  !(15 | lib.contracts.IsContract (lib.numbers.MultipleOf 4)),
]
in
let arraysTests = [
  [1, 2, 3] | lib.contracts.IsContract (lib.arrays.IsSet),
  !([1, 2, 2, 3, 2, 1] | lib.contracts.IsContract (lib.arrays.IsSet)),
  [1, 2, 3] | lib.contracts.IsContract (lib.arrays.Length { min = 2 }),
  [1, 2, 3] | lib.contracts.IsContract (lib.arrays.Length { min = 1, max = 3 }),
  !([1, 2, 3] | lib.contracts.IsContract (lib.arrays.Length { min = 4, max = 5 })),
  [1, 2, 3, "1"] | lib.contracts.IsContract (lib.arrays.Contains { min = 1, } String),
  !([1, 2, 3, ] | lib.contracts.IsContract (lib.arrays.Contains { min = 1, } String)),
  [1, 2, 3, ] | lib.contracts.IsContract (lib.arrays.Length { min = 1, max = 3 }),
  !([] | lib.contracts.IsContract (lib.arrays.Length { min = 1, max = 3 })),
  !([1, 2, 3, 4, 5] | lib.contracts.IsContract (lib.arrays.Length { min = 1, max = 3 })),
  ["first", "second", ] | lib.contracts.IsContract (lib.arrays.Tuple [ String, String, Number ] 'Exact),
  ["first", "second", 1] | lib.contracts.IsContract (lib.arrays.Tuple [ String, String, Number ] 'Exact),
  # ["first", "second", 1] | lib.contracts.IsContract (lib.arrays.Tuple [ String, String, Number ] 'AdditionalItems String)
]
in
let formatsTests = [

  # Valid Guids
  "639addf5-9297-4749-ae1e-ac1f9de1cbf3" | lib.contracts.IsContract lib.contracts.UUID,
  "{639addf5-9297-4749-ae1e-ac1f9de1cbf3}" | lib.contracts.IsContract lib.contracts.UUID,
  "(639addf5-9297-4749-ae1e-ac1f9de1cbf3)" | lib.contracts.IsContract lib.contracts.UUID,
  "639addf592974749ae1eac1f9de1cbf3" | lib.contracts.IsContract lib.contracts.UUID,

  #Invalid Guids
  !("639addf5-9297-4749-ae1e-ac1f9de1cbzz" | lib.contracts.IsContract lib.contracts.UUID),
  !("639addf5-9297-4749-ae1e-ac1f9de1c3" | lib.contracts.IsContract lib.contracts.UUID),
  !("{639addf592974749ae1eac1f9de1c3}" | lib.contracts.IsContract lib.contracts.UUID),
  !("(639addf592974749ae1eac1f9de1c3)" | lib.contracts.IsContract lib.contracts.UUID),
  !("{639addf592974749ae1eac1f9de1c3)" | lib.contracts.IsContract lib.contracts.UUID),
  !("639addf592974749ae1eac1f9de1c3)" | lib.contracts.IsContract lib.contracts.UUID),
  !("0000000" | lib.contracts.IsContract lib.contracts.UUID),

  # IPv4
  "0.0.0.0" | lib.contracts.IsContract lib.networking.IPv4,
  "255.255.255.255" | lib.contracts.IsContract lib.networking.IPv4,
  !("123.555.123.123" | lib.contracts.IsContract lib.networking.IPv4),

  # IPv6
  # "::1" | lib.contracts.IsContract lib.Networking.IPv6,
  # "0000:0000::1" | lib.contracts.IsContract lib.Networking.IPv6,
  # "0000::1" | lib.contracts.IsContract lib.Networking.IPv6,
  # "2001:db8::ff00:42:8329" | lib.contracts.IsContract lib.Networking.IPv6,
]
in
let recordTests = [
  let val = { a = "test" } in
  (
    val
      | lib.records.JsonObject
        {
          a = { optional = false, contract = String },
          b = { optional = true, contract = Number }
        }
        {}
        false
  ) == val,
  (
    { a = { b = 1, c = "3" } }
      | lib.records.JsonObject
        {
          a = {
            optional = false,
            contract = (
              lib.records.JsonObject
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
