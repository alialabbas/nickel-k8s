let schema_lib = import "../nickel-schema.ncl" in
let lib = import "../lib.ncl" in
# TODO: For now we are forcing laziness to test arrays and objects fully.
# BUG: oneOf in this schema doesn't force eager evaluation
let defs = { dummy = { oneOf = [{ type = "object" }], not = { type = "object" } } } in

let const_tests =
  let schema = { const = "string-const" } in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    "string-const" | lib.contracts.IsContract contract,
    !("invalid" | lib.contracts.IsContract contract),
    !(1 | lib.contracts.IsContract contract),
  ]
in

let enum_tests =
  let enum_with_no_type =
    let schema = { enum = [1, false, {}, null, "enum"] } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      (false | lib.contracts.IsContract contract),
      ({} | lib.contracts.IsContract contract),
      ("enum" | lib.contracts.IsContract contract),
      (1 | lib.contracts.IsContract contract),
      (null | lib.contracts.IsContract contract),
      !(2 | lib.contracts.IsContract contract),
    ]
  in
  let enum_with_type =
    let schema = { type = "number", enum = [10, 20, 30] } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      (10 | lib.contracts.IsContract contract),
      (20 | lib.contracts.IsContract contract),
      !(22 | lib.contracts.IsContract contract),
    ]
  in
  let enum_illogical =
    let schema = { type = "string", enum = [10, 20, 30] } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      !(10 | lib.contracts.IsContract contract),
      !(20 | lib.contracts.IsContract contract),
      !(22 | lib.contracts.IsContract contract),
      !("10" | lib.contracts.IsContract contract),
    ]
  in
  std.test.assert_all (enum_with_no_type @ enum_with_type @ enum_illogical)
in

let number_tests =
  let basic_tests =
    let schema = { type = "number" } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      1 | lib.contracts.IsContract contract,
      -1 | lib.contracts.IsContract contract,
      1.5 | lib.contracts.IsContract contract,
      !("1" | lib.contracts.IsContract contract),
      !(false | lib.contracts.IsContract contract),
      !({} | lib.contracts.IsContract contract),
      !(null | lib.contracts.IsContract contract),
    ]
  in
  let multiple_of_tests =
    let schema = { type = "number", multipleOf = 10 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      (10 | lib.contracts.IsContract contract),
      (20 | lib.contracts.IsContract contract),
      !(24 | lib.contracts.IsContract contract),
      !(1.5 | lib.contracts.IsContract contract),
    ]
  in
  let minimum_tests =
    let schema = { type = "number", minimum = 10 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      (10 | lib.contracts.IsContract contract),
      !(9 | lib.contracts.IsContract contract),
    ]
  in
  let maximum_tests =
    let schema = { type = "number", maximum = 100 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      (100 | lib.contracts.IsContract contract),
      !(101 | lib.contracts.IsContract contract),
    ]
  in
  let exclusive_minimum_tests =
    (
      let schema = { type = "number", exclusiveMinimum = 10 } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        (11 | lib.contracts.IsContract contract),
        !(10 | lib.contracts.IsContract contract),
        !(9 | lib.contracts.IsContract contract),
      ]
    )
    @ (
      let schema = { type = "number", minimum = 10, exclusiveMinimum = true } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        (11.1 | lib.contracts.IsContract contract),
        !(10 | lib.contracts.IsContract contract),
        !(9 | lib.contracts.IsContract contract),
      ]
    )
    @ (
      let schema = { type = "number", minimum = 10, exclusiveMinimum = false } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        (11.1 | lib.contracts.IsContract contract),
        (10 | lib.contracts.IsContract contract),
        !(9 | lib.contracts.IsContract contract),
      ]
    )
  in
  let exclusive_maximum_tests =
    (
      let schema = { type = "number", exclusiveMaximum = 10 } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        (9 | lib.contracts.IsContract contract),
        !(10 | lib.contracts.IsContract contract),
        !(11 | lib.contracts.IsContract contract),
      ]
    )
    @ (
      let schema = { type = "number", maximum = 10, exclusiveMaximum = true } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        !(11 | lib.contracts.IsContract contract),
        !(10 | lib.contracts.IsContract contract),
        (9 | lib.contracts.IsContract contract),
      ]
    )
    @ (
      let schema = { type = "number", maximum = 10, exclusiveMaximum = false } in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        (9 | lib.contracts.IsContract contract),
        (10 | lib.contracts.IsContract contract),
        !(11 | lib.contracts.IsContract contract),
      ]
    )
  in

  std.test.assert_all (
    basic_tests
    @ multiple_of_tests
    @ minimum_tests
    @ maximum_tests
    @ exclusive_minimum_tests
    @ exclusive_maximum_tests
  )
in

let integer_tests =
  let schema = { type = "integer" } in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    1 | lib.contracts.IsContract contract,
    -1 | lib.contracts.IsContract contract,
    !(1.5 | lib.contracts.IsContract contract),
    !("1" | lib.contracts.IsContract contract),
    !(false | lib.contracts.IsContract contract),
    !({} | lib.contracts.IsContract contract),
    !(null | lib.contracts.IsContract contract),
  ]
in

let string_tests =
  let basic =
    let schema = { type = "string" } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("1" | lib.contracts.IsContract contract),
      !(1 | lib.contracts.IsContract contract),
      !(-1 | lib.contracts.IsContract contract),
      !(1.5 | lib.contracts.IsContract contract),
      !(false | lib.contracts.IsContract contract),
      !({} | lib.contracts.IsContract contract),
      !(null | lib.contracts.IsContract contract),
    ]
  in
  let min_length =
    let schema = { type = "string", minLength = 3 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("fun" | lib.contracts.IsContract contract),
      !("no" | lib.contracts.IsContract contract),
    ]
  in
  let max_length =
    let schema = { type = "string", maxLength = 3 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("yes" | lib.contracts.IsContract contract),
      !("nono" | lib.contracts.IsContract contract),
    ]
  in
  let pattern =
    let schema = { type = "string", pattern = "^[0-9]*$" } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("" | lib.contracts.IsContract contract),
      ("0101" | lib.contracts.IsContract contract),
      !("nono" | lib.contracts.IsContract contract),
    ]
  in
  let format_tests =
    let schema = { type = "string", format = "uuid" } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("692441ac-c781-4f6b-a3c7-4ae847b51a27" | lib.contracts.IsContract contract),
      !("invalid" | lib.contracts.IsContract contract),
    ]
  in
  let mixed =
    let schema = { type = "string", pattern = "^[0-9]*$", minLength = 2, maxLength = 4 } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ("101" | lib.contracts.IsContract contract),
      ("0101" | lib.contracts.IsContract contract),
      !("1" | lib.contracts.IsContract contract),
      !("01011" | lib.contracts.IsContract contract),
      !("nono" | lib.contracts.IsContract contract),
      !("" | lib.contracts.IsContract contract),
    ]
  in
  std.test.assert_all (
    basic
    @ min_length
    @ max_length
    @ pattern
    @ format_tests
    @ mixed
  )
in

let array_tests =
  let array_of_anything_tests =
    let schema = { type = "array", } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ([] | lib.contracts.IsContract contract),
      (
        [
          1,
          -1,
          1.5,
          true,
          false,
          { first = 1 },
          { nested = { more-nested = 1 } },
          null,
          "string"
        ] | lib.contracts.IsContract contract
      ),
      !("1" | lib.contracts.IsContract contract),
      !(1 | lib.contracts.IsContract contract),
      !(-1 | lib.contracts.IsContract contract),
      !(1.5 | lib.contracts.IsContract contract),
      !(false | lib.contracts.IsContract contract),
      !({} | lib.contracts.IsContract contract),
      !(null | lib.contracts.IsContract contract),
    ]
  in

  let array_of_numbers =
    let schema = { type = "array", items = { type = "number" }, definitions = defs } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ([] | lib.contracts.IsContract contract),
      (
        [
          1,
          -1,
          1.5,
        ] | lib.contracts.IsContract contract
      ),
      !(
        [
          1,
          -1,
          1.5,
          true,
          false,
          { first = 1 },
          { nested = { more-nested = 1 } },
          null,
          "string"
        ] | lib.contracts.IsContract contract
      ),
    ]
  in

  let array_with_tuple_tests =
    (
      let schema = {
        type = "array",
        prefixItems = [
          { type = "number" },
          { type = "string" },
        ],
      }
      in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        ([] | lib.contracts.IsContract contract),
        ([1] | lib.contracts.IsContract contract),
        ([1, "string"] | lib.contracts.IsContract contract),
        ([1, "also", "can", "add", "more", true ] | lib.contracts.IsContract contract),
        !(["string", 1] | lib.contracts.IsContract contract),
      ]
    )
    @ (
      let schema = {
        type = "array",
        items = false,
        prefixItems = [
          { type = "number" },
          { type = "string" },
        ],
      }
      in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        ([] | lib.contracts.IsContract contract),
        ([1] | lib.contracts.IsContract contract),
        ([1, "string"] | lib.contracts.IsContract contract),
        !([1, "also", "can't", "add", "more", false ] | lib.contracts.IsContract contract),
        !(["string", 1] | lib.contracts.IsContract contract),
      ]
    )
  in

  let unique_tests =
    let schema = {
      type = "array",
      uniqueItems = true,
    }
    in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ([] | lib.contracts.IsContract contract),
      ([1, 2, 3, 4] | lib.contracts.IsContract contract),
      !([1, 2, 1, 3, 4] | lib.contracts.IsContract contract),
      !([1, 1, 1, ] | lib.contracts.IsContract contract),
    ]
  in

  let array_length_tests =
    let min_items_tests =
      let schema = {
        type = "array",
        minItems = 1,
      }
      in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        ([1] | lib.contracts.IsContract contract),
        !([] | lib.contracts.IsContract contract),
      ]
    in
    let max_items_tests =
      let schema = {
        type = "array",
        maxItems = 1,
      }
      in
      let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
      [
        ([1] | lib.contracts.IsContract contract),
        ([] | lib.contracts.IsContract contract),
        !([1, 2] | lib.contracts.IsContract contract),
      ]
    in min_items_tests
  in
  std.test.assert_all (
    array_of_anything_tests
    @ array_of_numbers
    @ array_with_tuple_tests
    @ array_length_tests
    @ unique_tests
  )
in

let object_tests =
  let open_object_tests =
    let schema = { type = "object", additionalProperties = true, } in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ({} | lib.contracts.IsContract contract),
      # BUG: this returns empty contract {} due to options
      (
        {
          string = "string",
          number = 1,
          bool = true,
          object = { nested = true, }
        } | lib.contracts.IsContract contract
      ),
      !("1" | lib.contracts.IsContract contract),
      !(1 | lib.contracts.IsContract contract),
      !(-1 | lib.contracts.IsContract contract),
      !(1.5 | lib.contracts.IsContract contract),
      !(false | lib.contracts.IsContract contract),
      !(null | lib.contracts.IsContract contract),
    ]
  in
  let object_properties_only_tests =
    let schema = {
      type = "object",
      additionalProperties = false,
      properties = {
        number = { type = "number" },
        string = { type = "string" },
        bool = { type = "boolean" },
        "null" = { type = "null" },
        object = { type = "object", additionalProperties = true, },
        integer = { type = "integer" },
      },
      definitions = defs,
    }
    in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ({} | lib.contracts.IsContract contract),
      (
        {
          string = "string",
          number = 1.5,
          integer = 1,
          bool = true,
          object = { nested = true, }
        } | lib.contracts.IsContract contract
      ),
      !(
        {
          string = 1,
          number = "1.5",
          integer = 1.4,
          bool = null,
          object = "string"
        } | lib.contracts.IsContract contract
      ),
      !("1" | lib.contracts.IsContract contract),
      !(1 | lib.contracts.IsContract contract),
      !(-1 | lib.contracts.IsContract contract),
      !(1.5 | lib.contracts.IsContract contract),
      !(false | lib.contracts.IsContract contract),
      !(null | lib.contracts.IsContract contract),
    ]
  in
  let pattern_properties_only =
    let schema = {
      type = "object",
      patternProperties = {
        "^\\." = { type = "string" },
        "^\\$" = {
          type = "number"
        }
      },
      definitions = defs
    }
    in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    []
  in
  let additional_properties_only =
    let schema = {
      type = "object",
      additionalProperties = { type = "string" },
      definitions = defs
    }
    in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ({} | lib.contracts.IsContract contract),
      ({ first = "string" } | lib.contracts.IsContract contract),
      !({ first = 1 } | lib.contracts.IsContract contract),
    ]
  in
  let dependent_required =
    let schema = {
      type = "object",
      properties = { first = {}, second = {} },
      dependentRequired = { first = ["second"] }
    }
    in
    let contract = (schema_lib.schema_to_nicke schema) in
    [
      {} | lib.contracts.IsContract contract,
      { first = 1, second = 1 } | lib.contracts.IsContract contract,
      !({ first = 1 } | lib.contracts.IsContract contract),
    ]
  in
  let mixed_objects =
    let schema = {
      type = "object",
      properties = {
        first = { type = "number", },
        second = {},
      },
      patternProperties = {
        "^\\." = { type = "string" }
      },
      additionalProperties = { type = "array" },
      dependentRequired = { first = ["second"] }
    }
    in
    let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
    [
      ({ first = 1, second = true } | lib.contracts.IsContract contract),
      ({ ".test" = "string" } | lib.contracts.IsContract contract),
      ({ additional = [1, false ] } | lib.contracts.IsContract contract),
      ({ first = 1, second = true, ".test" = "string", additional = [1, false ] } | lib.contracts.IsContract contract),
      !({ first = "fail", second = true, ".test" = "string", additional = [1, false ] } | lib.contracts.IsContract contract),
      !({ first = 1, second = true, ".test" = null, additional = [1, false ] } | lib.contracts.IsContract contract),
      !({ first = 1, second = true, ".test" = "string", additional = {}, } | lib.contracts.IsContract contract),
    ]
  in
  std.test.assert_all (
    open_object_tests
    @ object_properties_only_tests
    @ pattern_properties_only
    @ additional_properties_only
    @ mixed_objects
  )
in

let null_tests =
  let schema = { type = "null", } in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    (null | lib.contracts.IsContract contract),
    !("123" | lib.contracts.IsContract contract),
  ]
in

let multiple_types =
  let schema = { type = ["string", "null"] } in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    ("valid" | lib.contracts.IsContract contract),
    (null | lib.contracts.IsContract contract),
    !(false | lib.contracts.IsContract contract),
  ]
in

let empty_schema_tests =
  let schema = {} in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    (1 | lib.contracts.IsContract contract),
    (false | lib.contracts.IsContract contract),
    (null | lib.contracts.IsContract contract),
    ({} | lib.contracts.IsContract contract),
    ({ first = 1, second = "two", } | lib.contracts.IsContract contract),
    (1.5 | lib.contracts.IsContract contract),
    ("20%" | lib.contracts.IsContract contract),
    ([] | lib.contracts.IsContract contract),
    ([1, false, {}] | lib.contracts.IsContract contract),
  ]
in
let one_of_tests =
  let schema = {
    oneOf = [
      {
        type = "number",
      },
      { type = "string", }
    ]
  }
  in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    (1 | lib.contracts.IsContract contract),
    ("string" | lib.contracts.IsContract contract),
    !(null | lib.contracts.IsContract contract)
  ]
in
let any_of_tests =
  let schema = {
    anyOf = [
      {
        type = "array",
      },
      {
        type = "object",
        additionalProperties = true,
      }
    ],
  }
  in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  # TODO: why this breaks on anyOf
  std.test.assert_all [
    (["yes", "no", true, false ] | lib.contracts.IsContract contract),
    ({ yes = true, no = false } | lib.contracts.IsContract contract),
    !(1 | lib.contracts.IsContract contract),
    !("string" | lib.contracts.IsContract contract),
  ]
in

let not_tests =
  let schema = { not = { type = "string" } } in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    (1 | lib.contracts.IsContract contract),
    ([] | lib.contracts.IsContract contract),
    !("string" | lib.contracts.IsContract contract),
  ]
in

let all_of_tests =
  let schema = {
    allOf = [
      { type = "number", minimum = 10 },
      { type = "integer", maximum = 20 }
    ]
  }
  in
  let contract = (schema_lib.schema_to_nickel { lazy = false } schema) in
  std.test.assert_all [
    (10 | lib.contracts.IsContract contract),
    !(10.1 | lib.contracts.IsContract contract),
    !(21 | lib.contracts.IsContract contract),
  ]
in

{
  const = const_tests,
  enum = enum_tests,
  numbers = number_tests,
  integers = integer_tests,
  strings = string_tests,
  arrays = array_tests,
  objects = object_tests,
  nulls = null_tests,
  empty = empty_schema_tests,
  array_types = multiple_types,
  oneof = one_of_tests,
  anyof = any_of_tests,
  not = not_tests,
  allof = all_of_tests,
}
