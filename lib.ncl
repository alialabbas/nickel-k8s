let validLabel
  | doc "label and annotation validation, alphanumeric, _, - or ."
  = fun str =>
    std.string.is_match
      "^[a-zA-Z0-9]([-_/\\.a-zA-Z0-9]*[a-zA-Z0-9]\\/?[a-zA-Z0-9]*[a-zA-Z0-9]?)?$"
    # "[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*"
      str
in
let OnlyWhenInOrNotIn
  | doc "Selector values need to be empty if the operator is Exist or DoesNotExist, and In or NotIn, values can't be empty"
  = fun operator =>
    std.contract.from_validator (fun value =>
      operator
      |> match {
        "In" => 'Ok,
        "NotIn" => 'Ok,
        "Exists" => 'Error { message = "Exists and DoesNotExist can't have values defined" },
        "DoesNotExist" => 'Error { message = "Exists and DoesNotExist can't have values defined" },
        _ => 'Error { message = "Unkown Operator %{std.to_string operator}" },
      }
    )
in
{
  k8s
    | doc m%"
        Collection of K8s Contracts and Utility functions
      "%
    = {
      Name
        | doc m%"
            Kubernetes Metadata.Name based on RFC1123, lowercase alphanumeric and '-'
            ```nickel
            "this-is-valid" | Name
            ```
          "%
        = std.contract.from_predicate (fun name => std.string.is_match "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" name),

      Resource
        | doc m%" Kubernetes compute resource, cpu and memory
          ```nickel
          1000  | Resource
          ```
          Or
          ```nickel
          "100Mi"  | Resource
          ```
        "%
        =
          std.contract.from_predicate (fun val => std.is_number val || std.string.is_match "^[0-9]+(\\.[0-9]+)?(mi?|k|Ki|Mi?|Gi?|Ti?|Pi?|Ei?)?$" val),

      PortOrName
        | doc "Define a port either by standard port range a port name like http, grpc, etc."
        =
          std.contract.custom (fun label port =>
            let
              port_name_check = std.contract.apply Name label port,
              port_number_check = std.contract.apply networking.Port label port,
            in
            std.typeof port
            |> match {
              'String => 'Ok port_name_check,
              'Number => 'Ok port_number_check,
              _ => 'Error { message = "Expected either a port name or port number, got neither" },
            }
          ),

      Manifest
        | doc m%"KubeResrouce requires apiVersion, kind and metadata.name"%
        = { apiVersion | String, kind | String, metadata | { name | String, .. }, .. },

      List
        | doc m%"KubeList is a list of resources of various types"%
        = { apiVersion = "v1", kind = "List", items | Array Manifest },
      Metadata
        | doc "ObjectMeta is metadata that all persisted resources must have, which includes all objects users must create."
        = {
          labels | Labels | optional,
          annotations | Annotations | optional,
          name | Name | optional,
          namespace | Name | optional,
          ..
        },
      ResourceMetadata
        | doc "Extension of Metadata, includes metadata.name, the other one is used in embedded resources"
        = { name | Name } & Metadata,

      ValidLabel = std.contract.from_predicate (fun val => validLabel val),

      Annotations
        | doc "Validate a given record is a valid kube annotation"
        =
          std.contract.from_predicate (fun val =>
            std.array.all
              (fun record => (validLabel record.field))
              (std.record.to_array val)
          ),

      Labels
        | doc "Contract enforcing a record is a valid kube labels"
        =
          std.contract.from_predicate (fun val =>
            std.array.all
              (fun record => (validLabel record.field) && (validLabel record.value))
              (std.record.to_array val)
          ),

      LabelSelector = {
        matchExpressions
          | Array {
            key | ValidLabel,
            operator | enum.StringOrEnum [| 'In, 'NotIn, 'Exists, 'DoesNotExist |],
            values | Array ValidLabel | optional | OnlyWhenInOrNotIn operator,
          }
          | optional,
        matchLabels | Labels | optional,
      },

      WorkloadSelector
        | doc m%"
            Similar to LabelSelector except that it is enforcing the minimal required properties for when a selector object used in workload
            e.g deploymentspec.selector requires matchExpressions or matchLabels to be specified
          "%
        =
          std.contract.custom (fun label value =>
            if std.is_record value
            && (std.record.has_field "matchLabels" value || std.record.has_field "matchExpressions" value) then
              'Ok (value | LabelSelector)
            else
              'Error { message = "Need to define at least `matchLabels` or `matchExpressions`" }
          ),

      to_bytes
        | doc "Convert Request/Limits to total bytes"
        | Resource -> Number
        = fun resource =>
          let allUnits = [| 'm, 'mi, 'k, 'Ki, 'M, 'Mi, 'G, 'Gi, 'T, 'Ti, 'P, 'Pi, 'E, 'Ei |] in
          let powerOf2 = std.number.pow 2 in
          let unit =
            resource
            |> std.string.characters
            |> std.array.filter (fun e => !std.string.is_match "^[0-9]*$" e)
            |> std.array.reduce_right (++) | std.enum.TagOrString | allUnits
          in
          let value =
            resource
            |> std.string.characters
            |> std.array.filter (fun e => std.string.is_match "^[0-9]*$" e)
            |> std.array.reduce_right (++)
            |> std.string.to_number
          in
          unit
          |> match {
            'k => value * 1e3,
            'M => value * 1e6,
            'G => value * 1e9,
            'T => value * 1e12,
            'P => value * 1e15,
            'E => value * 1e18,
            'm => value / 1000,
            'mi => value / 1024,
            'Ki => value * powerOf2 10,
            'Mi => value * powerOf2 20,
            'Gi => value * powerOf2 30,
            'Ti => value * powerOf2 40,
            'Pi => value * powerOf2 50,
            'Ei => value * powerOf2 60,
          },

      from_map_to_list
        | doc "emulate kubenretes list-map type where a key in a list acts as the anchor for the object to allow list to be easily merged"
        = fun mergeKey value =>
          let r = (
            std.record.to_array value
            |> std.array.map (fun e =>
              let originalFieldValue =
                # if the string is a number, convert it back to a number since that what it was originally
                # TODO: is there a case where the value is always going to be a string and someone present it as a number only?
                # TODO: maybe doing this ourselves and typing it is a better way
                if e.field | contracts.IsContract std.string.NumberLiteral then
                  std.string.to_number e.field
                else
                  e.field
              in { "%{mergeKey}" = originalFieldValue } & e.value
            )
          )
          in
          std.typeof value
          |> match {
            'Record => r,
            _ => 'Error { message = "exected a record" }
          },

      from_list_to_map = fun key value =>
        std.typeof value
        |> match {
          'Array =>
            let acc = {} in
            std.array.fold_right
              (fun e acc =>
                let field = std.to_string e."%{key}" in
                if std.record.has_field field acc then
                  std.fail_with "Array is expected to not have a duplicate value on the merge key `%{key}`"
                else
                  { "%{field}" = std.record.remove key e } & acc
              )
              acc
              value,
          _ =>
            std.fail_with "Expected the data to be either formatted as a map or a list that can be converted, got instead %{std.to_string (std.typeof value)}"
        },
    },

  contracts = {

    ArrayOf
      | doc m%"
          Non-Lazy implementation of `Array` Contract. Useful in cases when a result is expected to be immediately available like in std.contract.any and such.
          ```nickel
          [1,2,3,4] | ArrayOf Number
          ```
      "%
      = fun element =>
        std.contract.custom (fun label value =>
          # TODO: restructure this to allow us to extract error messages more than just than the offending values
          # maybe since it is an array we should just do, value at i with error E
          let failedContracts =
            value
            |> std.array.fold_right
              (fun e acc =>
                std.contract.check
                  element
                  label
                  e
                |> match {
                  'Ok _ => acc,
                  'Error v => [e] @ acc
                }
              )
              []
          in
          std.typeof value
          |> match {
            'Array =>
              if std.array.length failedContracts == 0 then
                'Ok value
              else
                'Error {
                  message = "Some array elements don't match their contract\noffending values:\n%{std.serialize 'Json failedContracts}",
                  notes = []
                },
            t =>
              'Error {
                message = "Expected an array, got %{std.to_string t}"
              },
          }
        ),

    IsContract
      | doc m%"
      Utility test method to check if a value is valid against a contract. Doesn't work with records and arrays since those are lazy by design.
      "%
      = fun contract =>
        std.contract.custom (fun label value =>
          std.contract.check contract label value
          |> match {
            'Ok _ => 'Ok true,
            'Error _ => 'Ok false
          }
        ),

    "Bool" =
      std.contract.from_validator (fun value =>
        let type = std.typeof value in
        if type != 'Bool then
          'Error { message = "Expected a `Bool`, got `%{std.to_string type}`" }
        else
          'Ok
      ),

    "Number" =
      std.contract.from_validator (fun value =>
        let type = std.typeof value in
        if type != 'Number then
          'Error { message = "Expected a number, got %{std.to_string type}" }
        else
          'Ok
      ),

    "String" =
      std.contract.from_validator (fun value =>
        let type = std.typeof value in
        if type != 'String then
          'Error { message = "Expected a string, got %{std.to_string type}" }
        else
          'Ok
      ),
    Equal
      | doc "Equality Contract"
      = fun equal =>
        std.contract.custom (fun label value =>
          if value == equal then
            'Ok value
          else
            # TODO: stringify records here
            'Error { message = "Expected value to be equal to %{std.to_string (std.serialize 'Json equal)}" }
        ),

    # TODO: check this contract failing, thinking the value is function
    AnyOf
      | doc "Contract for checking if an array has a specific length, min, max or both"
      | Array Dyn -> Dyn
      = fun contracts =>
        std.contract.custom (fun label value =>
          let checks =
            std.array.fold_right
              (fun c acc =>
                acc @ [std.contract.check c label value]
              )
              []
              contracts
          in
          let errors =
            std.array.fold_right
              (fun e acc =>
                e
                |> match {
                  'Error err if std.record.has_field "message" err => acc @ [err.message],
                  _ => acc
                }
              )
              []
              checks
          in
          let validations = checks |> std.array.filter (fun e => e |> match { 'Ok _ => true, _ => false }) in
          let len = std.array.length validations in
          if len == 0 then
            'Error { message = "Didn't match any of the applied contracts", notes = errors }
          else
            'Ok value
        ),

    OneOf
      | doc "Contract for checking if an array has a specific length, min, max or both"
      | Array Dyn -> Dyn
      = fun contracts =>
        std.contract.custom (fun label value =>
          let checks =
            std.array.fold_right
              (fun c acc =>
                acc @ [std.contract.check c label value]
              )
              []
              contracts
          in
          let errors =
            std.array.fold_right
              (fun e acc =>
                e
                |> match {
                  'Error err if std.record.has_field "message" err => acc @ [err.message],
                  _ => acc
                }
              )
              []
              checks
          in
          let validations = checks |> std.array.filter (fun e => e |> match { 'Ok _ => true, _ => false }) in
          let len = std.array.length validations in
          if len != 1 then
            'Error { message = "OneOf matched against %{std.to_string len} contracts\n%{std.serialize 'Json errors}", notes = errors }
          else
            'Ok value
        ),

    UUID =
      let IsNGuid = fun v =>
        std.string.is_match
          "^[0-9a-f]{8}[0-9a-f]{4}[0-9a-f]{4}[0-9a-f]{4}[0-9a-f]{12}$"
          v
      in
      let IsDGuid = fun v =>
        std.string.is_match
          "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          v
      in
      let IsBGuid = fun v =>
        std.string.is_match
          "^\\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}$"
          v
      in
      let IsPGuid = fun v =>
        std.string.is_match
          "^\\([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\)$"
          v
      in
      std.contract.from_validator (match {
        t if std.typeof t != 'String =>
          'Error {
            message = "Expected a String, got %{std.to_string (std.typeof t)}"
          },
        s if std.string.length s < 32 =>
          'Error {
            message = "Got an invalid UUID length, need least 32 characters"
          },
        v if IsNGuid v
          || IsDGuid v
          || IsPGuid v
          || IsBGuid v => 'Ok,
        _ =>
          'Error {
            message = "Invalid Guid",
            notes = [
              "Guid have one of the following representations",
              "00000000000000000000000000000000",
              "00000000-0000-0000-0000-000000000000",
              "{00000000-0000-0000-0000-000000000000}",
              "(00000000-0000-0000-0000-000000000000)",
            ]
          },
      }
      ),

    DateTime = {
      Date =
        std.contract.from_validator (
          let isDateTime = fun v =>
            let segments = std.string.split "-" v in
            let year = std.array.at 0 segments in
            let month = std.array.at 1 segments in
            let day = std.array.at 2 segments in

            let isValidMonth = fun v =>
              std.string.length v == 2
              && (std.string.to_number v > 0 && std.string.to_number v <= 12)
            in

            let isValidDay = fun year month day =>
              let isDayValid = std.string.length day == 2 in
              let year = std.string.to_number year in
              let month = std.string.to_number month in
              let day = std.string.to_number day in
              month
              |> match {
                n if !isDayValid => false,
                1 => day > 0 && day <= 31,
                2 if year % 4 == 0 => day > 0 && day <= 29,
                2 => day > 0 && day <= 28,
                3 => day > 0 && day <= 31,
                4 => day > 0 && day <= 30,
                5 => day > 0 && day <= 31,
                6 => day > 0 && day <= 30,
                7 => day > 0 && day <= 31,
                8 => day > 0 && day <= 31,
                9 => day > 0 && day <= 30,
                10 => day > 0 && day <= 31,
                11 => day > 0 && day <= 30,
                12 => day > 0 && day <= 31,
              }
            in

            std.array.length segments == 3
            && std.string.is_match "^[0-9]{4}$" year
            && isValidMonth month
            && isValidDay year month day
          in
          match {
            v if !isDateTime v =>
              'Error {
                message = "%{v} is not a valid date time format",
                notes = ["e.g 2024-09-01 is valid but not 2024-9-1"],
              },
            _ => 'Ok,
          }
        ),
      Time
        | doc m%"
          Contract based on RFC3339
          https://datatracker.ietf.org/doc/html/rfc3339
        "%
        =
          std.contract.from_predicate (fun v =>
            std.string.is_match
              "^(?:[01]\\d|2[0-3]):(?:[0-5]\\d):(?:[0-5]\\d(\\+[0-9]{2}?(:[0-9]{2})?)?)$"
              v
          ),

      DateTime | doc "Simple ISO-8601 DateTime regex, doesn't check for leap years" =
        std.contract.from_predicate (fun v =>
          std.string.is_match
            "^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24\\:?00)([\\.,]\\d+(?!:))?)?(\\17[0-5]\\d([\\.,]\\d+)?)?([zZ]|([\\+-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?$"
            v
        ),

      Duration | doc "e.g P3D, P3Y" = std.contract.from_predicate (fun v => std.string.is_match "^P\\d+(D|M|Y)$" v),
    },
  },

  records = {
    NonEmpty =
      std.contract.from_validator (match {
        r if std.record.length r == 0 => 'Error { message = "Record can't be empty" },
        _ => 'Ok,
      }
      ),
    MutualExclusive
      | doc "enforce mutual exclusion on a set of record fields"
      = fun fields =>
        std.contract.custom (fun label record =>
          let declared_fields = std.record.fields record in
          let found =
            std.array.fold_right
              (fun field acc => if (std.record.has_field field record) then acc + 1 else acc)
              0
              fields
          in
          if found != 1 then
            let errMsg =
              fields
              |> std.array.fold_right (fun field acc => acc ++ " " ++ field) "The following fields are mutually exclusive:"
            in
            'Error { message = errMsg }
          else
            'Ok record
        ),
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
          { test = 1 } | { test = { type = Number, optional = false } }
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
        std.contract.custom (fun label value =>
          if std.typeof value != 'Record then
            'Error { message = "expected a record, got %{std.to_string (std.typeof value)}" }
          else
            let errors =
              std.typeof value
              |> match {
                'Record =>
                  std.record.to_array value
                  |> std.array.try_fold_left
                    (fun acc e =>
                      if std.typeof e.value == 'Record then
                        std.contract.check (IsRecord contract."%{e.field}") label e.value
                        |> match {
                          'Ok v => ('Ok v),
                          'Error val => ('Error val),
                        }
                      else
                        std.contract.check contract."%{e.field}" label e.value
                        |> match {
                          'Ok v => ('Ok v),
                          'Error val => ('Error val),
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
      = fun properties patternProperties additionalProperties =>
        let contract = fun label value =>
          # Edge Case: When no properties and patterns are set but additional is true, we will need to pass values as is
          # we first check pattern properties
          let result
          =
            # TODO: while this work, this can't report an aggregation of all errors when any of the contracts are records, including an error in the main one
            # If this is needed, it is possible to validate the required part and the optional part of each manually and aggregate that in the final result
            let result =
              std.record.to_array value
              |> std.array.fold_right
                (fun e acc =>
                  std.record.to_array patternProperties
                  |> std.array.fold_right
                    (fun p acc =>
                      if std.string.is_match p.field e.field then
                        let validationResult =
                          if std.typeof p.value == 'Record then
                            if (e.value | p.value) == e.value then "" else "pattern doesn't match"
                          else
                            std.contract.check p.value label e.value
                            |> match {
                              'Ok val => "",
                              'Error val =>
                                (
                                  "Property %{e.field} matches %{p.field} but doesn't match its contract:\n\t"
                                  ++ (std.record.get_or "message" "" val)
                                ) | String,
                            }
                        in
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
                        { checked = newResult, failed = newFailures, object = { "%{e.field}" | p.value = e.value } }
                      else
                        acc
                    )
                    acc
                )
                { checked = [], failed = [], object = {} }
            in
            result
          in

          # here we want to go over the defined properties and apply their IsContract
          # NOTE: while this look like a root level check only, each field contract could be yet another invocation to JsonObject
          let result #: { checked : Array String, failed : Array String, object : { _ : Dyn} }
          =
            std.record.to_array properties
            |> std.array.fold_right
              (fun e acc =>
                if !std.record.has_field e.field value && !e.value.optional then
                  {
                    checked = acc.checked,
                    failed = acc.failed @ ["Missing required field `%{e.field}`"],
                    object = acc.object
                  }
                else if !std.record.has_field e.field value && e.value.optional then
                  # missing an optional propertie, nothing to do here
                  acc
                else
                  std.contract.check e.value.contract label value."%{e.field}"
                  |> match {
                    'Ok _ =>
                      {
                        checked = acc.checked @ [e.field],
                        failed = acc.failed,
                        object =
                          let propertyContract = e.value.contract in
                          let c
                          # : { _ : Dyn }
                          = { "%{e.field}" | propertyContract = (value."%{e.field}") }
                          in
                          (
                            c
                            & acc.object
                          ) | { _ | Dyn }
                      },
                    # TODO: better error messaging
                    'Error val =>
                      {
                        checked = acc.checked,
                        failed = acc.failed @ ["`%{e.field}` doesn't match its specified contract\n" ++ "%{(std.record.get_or "message" "" val)  }"],
                        object = acc.object
                      },
                  }
              )
              result
          in

          # get the remaining properties and inject them
          let result =
            std.record.to_array value
            # TODO: most likely a lot of this contract validation logic could be in a helper method referenced in many places
            |> std.array.fold_right
              (fun e acc =>
                # Skip what was already checked
                if std.array.elem (e.field | Dyn) (result.checked | Array Dyn) then
                  acc
                  # NOTE: not obvious, but record contracts are lazying evaluated, meanging we need to apply them or
                  # the user wraps then in std.contract.custom and apply what we do here themselves
                  # TODO: remove me, this shouldn't happen
                else if std.typeof additionalProperties == 'Record then
                  if (e.value | additionalProperties) == e.value then
                    {
                      checked = acc.checked,
                      failed = acc.failed,
                      object = acc.object,
                    }
                  else
                    {
                      checked = acc.checked,
                      failed = acc.failed @ ["additional properties doesn't conform to its record contract"],
                      object = acc.object
                    }
                else if std.typeof additionalProperties == 'Bool then
                  {
                    checked = acc.checked @ [e.field],
                    failed = acc.failed,
                    object = (acc.object & { "%{e.field}" = e.value }) | { _ | Dyn },
                  }
                else
                  std.contract.check additionalProperties label e.value
                  |> match {
                    'Ok _ =>
                      {
                        checked = acc.checked @ [e.field],
                        failed = acc.failed,
                        object = (acc.object & { "%{e.field}" | additionalProperties = e.value }) | { _ | Dyn }
                      },
                    'Error _ =>
                      {
                        checked = acc.checked,
                        failed = acc.failed @ ["`%{e.field}` fails to match additional properties contract"],
                        object = acc.object
                      }
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
            'Error { message = (result.failed |> std.array.fold_right (fun e acc => "%{e}\n%{acc}") ""), notes = result.failed }
          else if (std.typeof additionalProperties == '"Bool")
          && additionalProperties == false
          && std.array.length remainingProperties > 0 then
            'Error { message = "record doesn't allow unchecked fields" ++ (std.serialize 'Json remainingProperties) | String, notes = remainingProperties }
          else
            # NOTE: this approach is not great and doesn't work well with merging contracts
            'Ok result.object
        in
        std.contract.custom contract | Dyn,

    get_value_at_path
    # : Array String -> { _ : Dyn } -> [| 'NotFound, 'Found |]
    = fun path value =>
      let leftOverPath = std.array.slice 1 (std.array.length path) path in
      let head = std.array.first path in
      # if we have anything left, recruse
      if head == "*" then
        let fields = std.record.fields value in
        if std.array.length fields > 1 then
          std.fail_with "When using a path with `*`, it is expected to only have a single field found more than 1"
        else
          get_value_at_path leftOverPath value
      else if !std.record.has_field head value then
        'NotFound
      else if std.array.length leftOverPath > 0 then
        get_value_at_path leftOverPath value."%{head}"
      else
        'Found value."%{head}",

    get_value_at_path_or_default = fun path default_val value =>
      let val = get_value_at_path path value in
      val |> match { 'Found v => v, 'NotFound => default_val },

    update_value_at_path
      | doc "Update a value at a given path"
      # : Array String -> Dyn -> { _ : Dyn } -> { _ : Dyn }
      = fun path updateVal value =>
        let leftOverPath = std.array.slice 1 (std.array.length path) path in
        let head = std.array.first path in
        if !std.record.has_field head value then
          value
        else if std.array.length leftOverPath > 0 then
          std.record.update head (update_value_at_path leftOverPath updateVal value."%{head}") value
        else
          std.record.update head updateVal value,
  },

  numbers = {
    InRange
      | doc "Enforce a number in range, both bounds inclusive"
      # | Number -> Bool -> Number -> Bool -> Dyn
      = fun min minInclusive max maxInclusive =>
        std.contract.all_of [
          (MinRange min minInclusive),
          (MaxRange max maxInclusive)
        ],

    MinRange
      | doc "Enforce a lower bound on a number"
      | Number -> Dyn
      = fun min minInclusive =>
        std.contract.custom (fun label value =>
          if minInclusive && value >= min then
            'Ok value
          else if value > min then
            'Ok value
          else
            'Error { message = "`%{std.to_string value}` should be greater than `%{std.to_string min}`" }
        ),

    MaxRange
      | doc "Enforce an upper bound on a number"
      | Number -> Dyn
      = fun min maxInclusive =>
        std.contract.custom (fun label value =>
          if maxInclusive && value <= min then
            'Ok value
          else if value < min then
            'Ok value
          else
            'Error { message = "`%{std.to_string value}` should be less than `%{std.to_string min}`" }
        ),

    MultipleOf
      | doc "JsonSchema multipleOf, i.e. multipleOf 10 will work for 150 but not 1"
      | Number -> Dyn
      = fun multiple =>
        std.contract.custom (fun label value =>
          if value % multiple == 0 then
            'Ok value
          else
            'Error { message = "`%{std.to_string value}` should be a multiple of `%{std.to_string multiple}`" }
        ),

    Percentage
      | doc "Custom type that can be represented as number, e.g. 10 or percentage 23%"
      =
        std.contract.custom (fun label value =>
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
        ),

    NumberOrPercentage
      | doc "Custom type that can be represented as number, e.g. 10 or percentage 23%"
      =
        std.contract.custom (fun label value =>
          std.typeof value
          |> match {
            'Number => 'Ok value,
            'String =>
              if std.string.is_match "^[0-9]+%$" value then
                'Ok value
              else
                'Error { message = "Expected a string number precented as percentage e.g. 10%" },
            _ => std.contract.blame_with_message "Expected either a number or a string percentage" label,
          }
        ),
  },

  strings = {

    MinLength
      | doc "Ensure a string is of a minimum range"
      | Number -> Dyn
      = fun min =>
        std.contract.custom (fun label value =>
          if std.string.length value < min then
            'Error { message = "string needs to at least have %{std.to_string min} characters" }
          else
            'Ok value
        ),

    MaxLength
      | doc "Ensure a string of a maxmimum length"
      | Number -> Dyn
      = fun max =>
        std.contract.custom (fun label value =>
          if std.string.length value > max then
            'Error { message = "string can only have at most %{std.to_string max} characters" }
          else
            'Ok value
        ),
    Regex
      | doc "Contract matching a string value against a regex"
      | String -> Dyn
      = fun regex =>
        std.contract.custom (fun label value =>
          if std.string.is_match regex value then
            'Ok value
          else
            'Error { message = "`%{value}` doesn't match regex `%{regex}`" }
        ),
    # = fun regex => std.contract.from_predicate (fun val => std.string.is_match regex val),
    join
      | doc "join array of string on character ignore empty strings"
      : String -> Array String -> String
      = fun joinChar values =>
        std.array.fold_right
          (fun e acc =>
            if acc == "" then
              e
            else if e != "" then e ++ joinChar ++ acc else acc
          )
          ""
          values
  },

  enum = {
    ArrayEnum
      | doc "Ensure a given value is part of a set"
      = fun elements =>
        std.contract.custom (fun label value =>
          std.array.elem value elements
          |> match {
            true => 'Ok value,
            false => 'Error { message = "Enum doesn't match expected enum values", notes = [(std.serialize 'Json elements)] }
          }
        ),
    StringOrEnum
      | doc "Similar to `std.enum.TagOrString | [| enums |]` expect that it can be applied inside other contracts safely"
      = fun enums =>
        std.contract.custom (fun label value =>
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

  arrays = {
    Length
      | doc "Contract for checking if an array has a specific length, min, max or both"
      | { min | std.number.PosNat | optional, max | std.number.PosNat | optional } -> Dyn
      = fun MinAndMax =>
        std.contract.custom (fun label value =>
          let t = std.typeof value in
          if t != 'Array then
            'Error { message = "Expected an Array, got %{std.to_string t}" }
          else
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
        std.contract.custom (fun label value =>
          let contractLength = std.array.length contracts in
          let valueLength = std.array.length value in
          if strict == 'Exact && std.array.length value > std.array.length contracts then
            'Error { message = "Array can't have more values than its expected types at each index. Expected: %{std.to_string contractLength} Got: %{std.to_string valueLength}" }
          else
            let length = if contractLength < valueLength then contractLength else valueLength in
            let result =
              (std.array.range 0 valueLength)
              |> std.array.map (fun i =>
                let v = std.array.at i value in
                let c = if i >= contractLength then let tagArg = std.enum.to_tag_and_arg strict in tagArg.arg else std.array.at i contracts in
                std.contract.check c label v
              )
              |> std.array.filter (fun e =>
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
        std.contract.custom (fun label value =>
          let foundContract =
            value
            |> std.array.map (fun e =>
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
        std.contract.custom (fun label value =>
          let nonUniqueItems =
            value
            |> std.array.fold_right
              (fun e acc => let hash = std.serialize 'Json e in if std.record.has_field hash acc then std.record.update hash false acc else std.record.update hash true acc
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

  networking
    | doc m%"Collection of networking related types, ports, ipv4, etc"%
    = {
      Port
        | doc m%"
            Valid port number between 0 to 65535

            ```nickel
            1234 | Port
            ```
        "%
        = numbers.InRange 0 true 65535 true,

      IPv6
        | doc "Contract ensuring the string is a valid ipv6 representation"
        =
          std.contract.custom (fun label value =>
            if std.string.find_all "::" value |> std.array.length > 1 || std.string.find_all ":::" value |> std.array.length > 0 then
              'Error {
                message = "%{value} is a not a valid ipv6"
              }
            else
              let result =
                std.string.split ":" value
                |> std.array.filter (fun e => e != "")
                |> std.array.all (fun e => std.string.is_match "^[0-9a-fA-F]{1,4}$" e)
              in
              if result then
                'Ok value
              else
                'Error { message = "%{value} is not a valid ipv6" }
          ),
      IPv4
        | doc "IPv4 address"
        =
          std.contract.from_predicate (fun ip =>
            let parts = std.string.split "." ip in
            if std.array.length parts == 4 then
              parts |> std.array.all (fun val => let n = std.string.to_number val in n >= 0 && n <= 255)
            else
              false
          ),
    },
}
