{
  IsContract = fun contract =>
    std.contract.custom
      (
        fun label value =>
          std.contract.check contract label value
          |> match {
            'Ok _ => 'Ok true,
            'Error _ => 'Ok false
          }
      ),
  # TODO: check this contract failing, thinking the value is function
  AnyOf
    | doc "Contract for checking if an array has a specific length, min, max or both"
    | Array Dyn -> Dyn
    = fun contracts =>
      std.contract.custom
        (
          fun label value =>
            let validations =
              std.array.fold_right
                (
                  fun c acc =>
                    # std.contract.check (std.contract.from_predicate (fun value => (value | c) == value)) label value
                    std.contracts.check c label value
                    |> match {
                      'Ok val => acc @ ['Ok val],
                      'Error _ => acc,
                    }
                )
                []
                contracts
              |> std.array.filter (fun e => e |> match { 'Ok _ => true, _ => false })
            in
            let len = std.array.length validations in
            if len == 0 then
              'Error { message = "Didn't match any of the applied contracts" }
            else
              'Ok value
        ),
  OneOf
    | doc "Contract for checking if an array has a specific length, min, max or both"
    | Array Dyn -> Dyn
    = fun contracts =>
      std.contract.custom
        (
          fun label value =>
            let validations =
              std.array.fold_right
                (
                  fun c acc =>
                    # std.contract.check (std.contract.from_predicate (fun value => (value | c) == value)) label value
                    std.contract.check c label value
                    |> match {
                      'Ok val => acc @ ['Ok val],
                      'Error _ => acc,
                    }
                )
                []
                contracts
              |> std.array.filter (fun e => e |> match { 'Ok _ => true, _ => false })
            in
            let len = std.array.length validations in
            if len == 0 then
              'Error { message = "Didn't match any of the applied contracts" }
            else if len > 1 then
              'Error { message = "matched against %{std.to_string len} contracts" }
            else
              'Ok value
        ),

  Records = {
    # there needs to be an IsRecord contract that allow us to check if a contract is valid or not
    # I guess this means any record needs to be modeled using this IsRecord/JsonObject model
    # AnyOf can't work with lazy contrats, OneOf can't, Not can't
    # need something we own that can do that
    # we are back to required vs optional part
    # TODO: extract out basic type validations
    # TODO: ensure we are validating record only
    # TODO: support required properties, how would this work for nested records?
    # The first level is easy we can just say this is good, get those properties and push it
    # I guess we need a more refined format maybe, if contract required are two properties, how do we pass the second part
    # i guess the value is always a record, one part is a contract, the other part is the optionality of the record.
    # This way, we can try check if the a field is optional or not, and also apply its contract
    # should also work for all contracts as well
    # yeah we really have to deconstruct the record ourservles and no way around making the object look stupid
    # How do we even optimize the object look. Send a hint when a contract is coming from bool combinator or has a bool combinator on the side
    # And basically from here we should be able to tell if a contract should be flattened when possible or we should just slap it all togheter
    # This will keep most generations to be same but then the crazy one will be gone
    # A good schema wouldn't have a nested chain of objects and instead would define each independently making it more readable
    IsRecord
      | doc m%"
          This is a non-lazy version of
          ```nickel
          { test = 1 }| { test | Number}
          ```
          The benefit of this contract is to allow us to have know if the record at this instance matches the model
          and returns back 'Ok and 'Error values. This allow us to consume records validation inside of any_of and all_of
          since those expect those values to be propagated back. The lazy version would always err which sometimes is not ideal

          ```nickel
          { test = 1 | { test = { type = Number, optional = false } }
          ```
        "%
      = fun contract =>
        # TODO: there is no way to do additional properties without passing a flag or something
        # this flag always represent the root level schema, so if we had a sub schema that would need to also be somehow called recusively with the flag
        # The root doesn't decidate what is open and what is not open
        # yeah no way around this other than additional properties.
        # the issue is the ugly code that would be generated
        # there is gonna be a parent contract. Modeled by itself, but then as we have yet another record it would need to be a JsonObject yet again to test what we want to test
        # neseted contracts, basically each time we generate, the included sub contract should be able to grok what's going on
        # will work but it means every generated code need to use this and not the basic contracts
        # i guess the issue stems from complex schemas that has multiple parts
        std.contract.custom
          (
            fun label value =>
              if std.typeof value != 'Record then
                'Error { message = "expected a record, got %{std.to_string (std.typeof value)}" }
              else
                let errors =
                  std.typeof value
                  |> match {
                    'Record =>
                      std.record.to_array value
                      |> std.array.try_fold_left
                        (
                          fun acc e =>
                            if std.typeof e.value == 'Record then
                              std.contract.check (IsRecord contract."%{e.field}") label e.value
                              |> match {
                                'Ok v => std.trace "record" ('Ok v),
                                'Error val => std.trace "here" ('Error val),
                              }
                            else
                              std.contract.check contract."%{e.field}" label e.value
                              |> match {
                                'Ok v => std.trace "ok normla" ('Ok v),
                                'Error val => std.trace "inhere" ('Error val),
                              }
                        )
                        'None,
                  }
                in
                errors
                |> match {
                  'None =>
                    'Error { message = "empty case" },
                  'Error _ =>
                    errors,
                  'Ok _ => 'Ok value,
                }
          ),
    JsonObject
      | doc m%"
          Represent a json record using standard json schema model for objects.
          Only use this when you want to code generation json schemas since most likely the code would look cleaner if you write your contract by hand.
        "%
      : { _ : Dyn } -> { _ : Dyn } -> Dyn -> Dyn
      = fun properties patternProperties additionalProperties =>
        let contract = fun label value =>
          # we first check pattern properties
          let result
            : { checked : Array String, failed : Array String }
            =
              # TODO: while this work, this can't report an aggregation of all errors when any of the contracts are records, including an error in the main one
              # If this is needed, it is possible to validate the required part and the optional part of each manually and aggregate that in the final result
              let result =
                std.record.to_array value
                |> std.array.fold_right
                  (
                    fun e acc =>
                      std.record.to_array patternProperties
                      |> std.array.fold_right
                        (
                          fun p acc =>
                            if std.string.is_match p.field e.field then
                              let validationResult =
                                if std.typeof p.value == 'Record then
                                  if (e.value | p.value) == e.value then "" else "pattern doesn't match"
                                else
                                  std.contract.check p.value label e.value
                                  |> match {
                                    'Ok val => "",
                                    'Error val => ("Property %{e.field} matches %{p.field} but doesn't match its contract:\n\t" ++ (std.record.get_or "message" "" val)) | String,
                                  }
                              in
                              # TODO: this could be written in a better way by contrcut
                              let newResult =
                                if validationResult == "" then
                                  acc.checked @ [e.field]
                                else
                                  acc.checked
                              in

                              let newFailures =
                                if validationResult != "" then
                                  acc.failed @ [validationResult]
                                else
                                  acc.failed
                              in
                              { checked = newResult, failed = newFailures }
                            else
                              acc
                        )
                        acc
                  )
                  { checked = [], failed = [] }
              in
              result
            in

          # we then get the properties that are part of the properties contract but assume they are correct
          # the returned result would be apply the properties contract checking their correctness
          let result =
            let record_contract_fields = std.record.fields_with_opts properties in
            std.record.fields_with_opts value
            |> std.array.fold_right
              (
                fun e acc =>
                  if std.array.any (fun p => p == e) record_contract_fields then { checked = acc.checked @ [e], failed = acc.failed } else acc
              )
              result
          in

          # get the remaining properties and inject them
          let result =
            if std.typeof additionalProperties == 'Bool then
              result
            else
              std.record.to_array value
              # TODO: most likely a lot of this contract validation logic could be in a helper method referenced in many places
              |> std.array.fold_right
                (
                  fun e acc =>
                    if std.array.elem (e.field | Dyn) (result.checked | Array Dyn) then
                      acc
                      # NOTE: not obvious, but record contracts are lazying evaluated, meanging we need to apply them or
                      # the user wraps then in std.contract.custom and apply what we do here themselves
                    else if std.typeof additionalProperties == 'Record then
                      if (e.value | additionalProperties) == e.value then { checked = acc.checked, failed = acc.failed } else { checked = acc.checked, failed = acc.failed @ ["additional properties doesn't conform to its record contract"] }
                    else
                      std.contract.check additionalProperties label e.value
                      |> match {
                        'Ok _ => { checked = acc.checked @ [e.field], failed = acc.failed },
                        'Error _ => { checked = acc.checked, failed = acc.failed @ ["`%{e.field}` fails to match additional properties contract"] }
                      }
                )
                result
          in

          let remainingProperties =
            std.record.fields value
            |> std.array.fold_right (fun e acc => if !std.array.elem (e | Dyn) (result.checked | Array Dyn) then acc @ [e] else acc) []
          in

          let type = std.typeof (value | Dyn) in

          if type != 'Record then
            'Error { message = "expected a record, got `%{std.string.from_enum type}`", notes = [] }
          else if std.array.length result.failed != 0 then
            'Error { message = "failed inside the contract", notes = result.failed }
          else if (std.typeof additionalProperties == '"Bool")
          && additionalProperties == false
          && std.array.length remainingProperties > 0 then
            'Error { message = "record doesn't allow unchecked fields", notes = remainingProperties }
          else
            # NOTE: this approach is not great and doesn't work well with merging contracts
            'Ok (value | properties)
        in
        std.contract.custom contract | Dyn,
  },

  Numbers = {
    # TODO: For best practice used Enums to expose some literal to the type to allow the end user understand what's happening
    InRange
      | doc "Enforce a number in range, both bounds inclusive"
      # | Number -> Bool -> Number -> Bool -> Dyn
      = fun min minInclusive max maxInclusive =>
        std.contract.all_of
          [
            (MinRange min minInclusive),
            (MaxRange max maxInclusive)
          ],

    MinRange
      | doc "Enforce a lower bound on a number"
      # | Number -> Bool -> Dyn
      = fun min minInclusive => std.contract.from_predicate (fun val => if minInclusive then val >= min else val > min),

    MaxRange
      | doc "Enforce an upper bound on a number"
      # | Number -> Bool -> Dyn
      = fun max maxInclusive => std.contract.from_predicate (fun val => if maxInclusive then val <= max else val < max),
    MultipleOf
      | doc "JsonSchema multipleOf, i.e. multipleOf 10 will work for 150 but not 1"
      # | Number -> Bool -> Dyn
      = fun multiple => std.contract.from_predicate (fun val => val % multiple == 0),

    Percentage
      | doc "Custom type that can be represented as number, e.g. 10 or percentage 23%"
      =
        std.contract.custom
          (
            fun label value =>
              std.typeof value
              |> match {
                'Number => 'Ok value,
                'String =>
                  if std.string.is_match "^[0-9]+%$" value then
                    'Ok value
                  else
                    'Error { message = "Expected a string number precented as percentage e.g. 10%" },
                _ => 'Error { message = "Expected either a number or a string percentage" },
              }
          )
  },

  Strings = {
    MinLength
      | doc "Ensure a string is of a minimum range"
      # | Number -> Bool -> Dyn
      = fun min => std.contract.from_predicate (fun val => std.string.length val >= min),
    MaxLength
      | doc "Ensure a string of a maxmimum length"
      # | Number -> Bool -> Dyn
      = fun max => std.contract.from_predicate (fun val => std.string.length val <= max),
    Regex
      | doc "Contract matching a string value against a regex"
      # | String -> Bool -> Dyn
      = fun regex => std.contract.from_predicate (fun val => std.string.is_match regex val)
  },

  UUID =
    std.contract.from_predicate
      (
        fun v =>
          std.string.is_match
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
            v
      ),

  DateTime = {
    Date =
      std.contract.from_predicate
        (
          fun v =>
            std.string.is_match
              "^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))"
              v
        ),
    Time =
      std.contract.from_predicate
        (
          fun v =>
            std.string.is_match
              "^(?:[01]\\d|2[0-3]):(?:[0-5]\\d):(?:[0-5]\\d(\\+[0-9]{2}?(:[0-9]{2})?)?)$"
              v
        ),

    DateTime | doc "Simple ISO-8601 DateTime regex, doesn't check for leap years"
      =
        std.contract.from_predicate
          (
            fun v =>
              std.string.is_match
                "^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24\\:?00)([\\.,]\\d+(?!:))?)?(\\17[0-5]\\d([\\.,]\\d+)?)?([zZ]|([\\+-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?$"
                v
          ),

    Duration | doc "e.g P3D, P3Y" = std.contract.from_predicate (fun v => std.string.is_match "^P\\d+(D|M|Y)$" v),
  },

  Enum = {
    StringOrEnum
      | doc "Similar to `std.enum.TagOrString | [| enums |]` expect that it can be applied inside other contracts safely"
      = fun enums =>
        std.contract.custom
          (
            fun label value =>
              let type = std.typeof value in
              type
              |> match {
                '"String" =>
                  let enum = std.enum.from_tag_and_arg { tag = "%{value}" } in
                  let result = std.contract.check enums label enum in
                  result |> match { 'Ok _ => 'Ok value, _ => result },
                'Enum =>
                  let result = std.contract.check enums label value in
                  result |> match { 'Ok _ => 'Ok value, _ => result },
                _ => 'Error { message = "Value is neither a string or an enum. Value type is: %{std.to_string type}" }
              }
          ),
  },

  Arrays = {
    Length
      | doc "Contract for checking if an array has a specific length, min, max or both"
      | { min | std.number.PosNat | optional, max | std.number.PosNat | optional } -> Dyn
      = fun MinAndMax =>
        std.contract.custom
          (
            fun label value =>
              MinAndMax
              |> match {
                {} => 'Ok value,
                { min } if std.array.length value >= min => 'Ok value,
                { max } if std.array.length value <= max => 'Ok value,
                { min, max } if std.array.length value >= min && std.array.length value <= max => 'Ok value,
                _ => 'Error { message = "Array doesn't satisfy the given constraints Min: %{std.to_string (std.record.get_or "min" "0" MinAndMax)}, Max: %{std.to_string (std.record.get_or "max" "+inf" MinAndMax)}" },
              }
          ),
    Tuple # TODO: this is missing items check to make sure the types of the additional items
      | doc "JsonSchema Array Tuple validation. Checks if every index of in the array matches a given schema"
      | Array Dyn -> [| 'Exact, 'AdditionalItems Dyn |] -> Dyn
      = fun contracts strict =>
        std.contract.custom
          (
            fun label value =>
              let contractLength = std.array.length contracts in
              let valueLength = std.array.length value in
              if strict == 'Exact && std.array.length value > std.array.length contracts then
                'Error { message = "Array can't have more values than its expected types at each index. Expected: %{std.to_string contractLength} Got: %{std.to_string valueLength}" }
              else
                let length = if contractLength < valueLength then contractLength else valueLength in
                let result =
                  (std.array.range 0 valueLength)
                  |> std.array.map
                    (
                      fun i =>
                        let v = std.array.at i value in
                        let c = if i >= contractLength then let tagArg = std.enum.to_tag_and_arg strict in tagArg.arg else std.array.at i contracts in
                        std.contract.check c label v
                    )
                  |> std.array.filter
                    (
                      fun e =>
                        e
                        |> match {
                          'Ok val => false,
                          'Error messages => true,
                        }
                    )
                in
                if std.array.length result == 0 then 'Ok value else std.array.first result
            # At this point we can actually know if we have more values and take the value of the enum and apply it to the rest of the array
            # %enum/get_arg% ('Left (1+1)) get the arg and we apply the contract to ecah type
            # simple conditional let first Chec and Rest of Check if available
          ),

    Contains
      | doc "ensure an array contains a specifc type with the specified minimum occurrance"
      | { min | Number, max | Number | optional, } -> Dyn -> Dyn
      = fun constraints contract =>
        std.contract.custom
          (
            fun label value =>
              let foundContract =
                value
                |> std.array.map
                  (
                    fun e =>
                      let result = std.contract.check contract label e in
                      result
                      |> match {
                        'Ok val => true,
                        'Error messages => false,
                      }
                  )
                |> std.array.filter (fun e => e)
              in
              constraints
              |> match {
                { min } =>
                  if foundContract |> std.array.length >= constraints.min then
                    'Ok value
                  else
                    'Error { message = "Expecting at least %{std.to_string constraints.min} of the passed contract" },
                { min, max } =>
                  let count = foundContract |> std.array.length in
                  if count >= constraints.min && count <= constraints.max then
                    'Ok value
                  else
                    'Error { message = "Expected at least %{std.to_string constraints.min} and at most %{std.to_string constraints.max} of the passed contract" }
              }
          ),
    # error reporting here... how will it look like
    IsSet
      | doc "Ensure an array can be represented as a set of unique items"
      =
        std.contract.custom
          (
            fun label value =>
              let nonUniqueItems =
                value
                |> std.array.fold_right
                  (
                    fun e acc => let hash = std.serialize 'Json e in if std.record.has_field hash acc then std.record.update hash false acc else std.record.update hash true acc
                  )
                  {}
                |> std.record.filter (fun k v => v == false)
              in
              if std.record.length nonUniqueItems > 0 then
                'Error { message = "Expected an array of unqiue values, found duplicates", }
              else
                'Ok value
          )
  },

  Networking
    | doc m%"Collection of networking related types, ports, ipv4, etc"%
    = {
      Port
        | doc "Valid port number between 0 to 65535"
        = Numbers.InRange 0 65535,

      IPAddr
        | doc "IPv4 address"
        =
          std.contract.from_predicate
            (
              fun ip =>
                let parts = std.string.split "." ip in
                if std.array.length parts == 4 then
                  parts |> std.array.all (fun val => let n = std.string.to_number val in n >= 0 && n <= 255)
                else
                  false
            ),
    },
}