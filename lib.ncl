let validLabel
  | doc "label and annotation validation, alphanumeric, _, - or ."
  = fun str =>
    std.string.is_match
      "^[a-zA-Z0-9]([-_/\\.a-zA-Z0-9]*[a-zA-Z0-9]\\/?[a-zA-Z0-9]*[a-zA-Z0-9]?)?$"
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

            # Examples

            ```nickel multiline
            "this-is-valid" | Name
            # "this-is-valid"

            "NOTVALID" | Name
            # => error: contract broken by a value

            (std.array.replicate 70 "a" |> std.string.join "") | Name
            # => error: contract broken by a value
            ```
          "%
        =
          std.contract.from_validator (fun name =>
            if std.string.length name > 63 then
              'Error { message = "Kube resources should be less than 63 characters" }
            else if !std.string.is_match "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" name then
              'Error { message = "Kube resource should be a valid DNS name" }
            else
              'Ok
          ),

      Resource
        | doc m%"
          Kubernetes compute resource, cpu and memory

          # Examples

          ```nickel multiline
          1000  | Resource
          # 1000

          "100Mi"  | Resource
          # "100Mi"

          "1000U" | Resource
          # => error: contract broken by a value
          ```
        "%
        =
          std.contract.from_predicate (fun val => std.is_number val || std.string.is_match "^[0-9]+(\\.[0-9]+)?(mi?|k|Ki|Mi?|Gi?|Ti?|Pi?|Ei?)?$" val),

      PortOrName
        | doc m%"
            Define a port either by standard port range a port name like http, grpc, etc.

            Examlpes

            ```nickel multiline
            27707 | PortOrName
            # 27707

            "http" | PortOrName
            # "http"
            ```
        "%
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
        | doc m%"
        KubeResrouce requires apiVersion, kind and metadata.name

        Examples

        ```nickel multiline
        { apiVersion = "myApiVersion", kind = "myApiKind", metadata.name = "my-resource-name" } | Manifest

        {} | Manifest
        # => error: missing definition for `apiVersion`
        ```
        "%
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
        | doc "Similar to `Metadata` but name is now a required field"
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
        | doc m%"
        Convert Request/Limits to total bytes

        # Examples
        to_bytes 100K
        100000
        "%
        | Resource -> Number
        = fun resource =>
          let allUnits = [| 'm, 'mi, 'k, 'Ki, 'M, 'Mi, 'G, 'Gi, 'T, 'Ti, 'P, 'Pi, 'E, 'Ei |] in
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
            'Ki => value * std.number.pow 2 10,
            'Mi => value * std.number.pow 2 20,
            'Gi => value * std.number.pow 2 30,
            'Ti => value * std.number.pow 2 40,
            'Pi => value * std.number.pow 2 50,
            'Ei => value * std.number.pow 2 60,
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

  semver = {
    Constraint
      | doc m%"
  Contract Ensuring a semantic version is meeting a specifc requirement
  "%
      = fun constraint => std.contract.from_validator (fun e => 'Ok),

    SemanticVersion
      | doc m%"
        Contract to ensure a semantic version matches a major/minor/patch

        # Example

        ```nickel multiline
        "1.1.1-alpha" | SemanticVersion

        "1.1.1-alpha." | SemanticVersion
        # => error: `1.1.1-alpha.` is not a valid semver

        "v1" | SemanticVersion

        "1" | SemanticVersion

        "1.1" | SemanticVersion

        "1.1.1" | SemanticVersion

        "1." | SemanticVersion
        # => error: `1.` is not a valid semver

        "1.1.1-" | SemanticVersion
        # => error: `1.1.1-` is not a valid semver
        ```
    "%
      =
        let is_valid_pre : String -> Bool = fun pre =>
          std.string.is_match "^[0-9a-zA-Z.-]*$" pre
          && (std.string.length pre == 0 || (std.string.characters pre |> std.array.last |> std.string.is_match "[.-]" |> (!)))
        in
        # TODO: technically not a semver?!
        let is_valid_major : String -> Bool = fun v => std.string.is_match "v?[0-9]+$" v in
        let is_valid_minor_or_patch : String -> Bool = fun v => std.string.is_match "v?[0-9]*$" v in

        std.contract.from_validator (fun ver =>
          let err = 'Error { message = "`%{ver}` is not a valid semver" } in
          if std.typeof ver != 'String then
            err
          else if std.string.is_match ".*[.-]$" ver then
            err
          else
            let is_valid_semver = fun major minor patch pre =>
              if is_valid_major major
              && is_valid_minor_or_patch minor
              && is_valid_minor_or_patch patch
              && is_valid_pre pre then
                'Ok
              else
                'Error { message = "`%{ver}` is not a valid semver" }
            in
            strings.splitN ver "." 2
            |> match {
              [major, minor, patch] =>
                let [patch, ..pre] = std.string.split "-" patch in
                let pre = std.string.join "" pre in
                is_valid_semver major minor patch pre,
              [major, maybe_minor_or_pre] =>
                let [minor, ..pre] =
                  let subStr = strings.splitN maybe_minor_or_pre "-" 1 in
                  if std.array.length subStr == 1 then
                    subStr @ [""]
                  else
                    subStr
                in
                let pre = std.string.join "" pre in
                is_valid_semver major minor "" pre,
              [major] => std.trace "%{major}" is_valid_semver major "" "" "",
              _ => 'Error { message = "`%{ver}` is not a valid semver" }
            }
        ),
  },

  contracts = {
    IfThenElse
      | doc m%"
    Conditonal contract evaluated against then else when the if part fails. Otherwise, check it against the then part.

    ```nickel multiline
    12 | IfThenElse Number (numbers.MultipleOf 2) String

    "test" | IfThenElse Number (numbers.MultipleOf 2) String

    3 | IfThenElse Number (numbers.MultipleOf 2) String
    # => error: `3` should be a multiple of `2`
    ```
    "%
      = fun ef zen els =>
        std.contract.custom (fun label value =>
          std.contract.check ef label value
          |> match {
            'Ok _ => std.contract.check zen label value,
            'Error _ => std.contract.check els label value,
          }
        ),
    ArrayOf
      | doc m%"
        Non-Lazy implementation of `Array` Contract. Useful in cases when a result is expected to be immediately available like in std.contract.any and such.

        # Examples

        ```nickel multiline
        [1,2,3,4] | ArrayOf Number

        [1,2,3] | ArrayOf String
        # => error: contract broken by a value

        [1,2,3, true ] | std.contract.any_of [ArrayOf String, ArrayOf Number]
        # => error: contract broken by a value
        ```
      "%
      = fun element =>
        std.contract.custom (fun lbl value =>
          if std.typeof value != 'Array then
            'Error {
              message = "Expected an array, got %{std.to_string (std.typeof value)}",
              blame_location = lbl
            }
          else
            value
            |> std.array.fold_left
              (fun acc e =>
                std.contract.check
                  element
                  lbl
                  e
                |> match {
                  'Ok _ => acc,
                  'Error e => 'Error e
                }
              )
              'Ok
            |> match {
              'Ok =>
                'Ok value,
              'Error e => 'Error e,
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

    UUID
      | doc m%"
    Check if a string value represent a guid

    # Examples

    ```nickel multiline
    "be39fd8b-6c60-43d6-83d9-bd01b5ce4b06" | UUID

    "be39fd8b6c6043d683d9bd01b5ce4b06" | UUID

    "{be39fd8b-6c60-43d6-83d9-bd01b5ce4b06}" | UUID

    "invalid-guid" | UUID
    # => error: contract broken by a value
    ```
    "%
      =
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
          let is_number = fun n => std.string.is_match "^[0-9]+$" n in
          let isDateTime = fun v =>
            let segments = std.string.split "-" v in
            let year = std.array.at 0 segments in
            let month = std.array.at 1 segments in
            let day = std.array.at 2 segments in

            let isValidMonth = fun v =>
              is_number v
              && std.string.length v == 2
              && (std.string.to_number v > 0 && std.string.to_number v <= 12)
            in

            let isValidDay = fun year month day =>
              let isDayValid = is_number day && std.string.length day == 2 in
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
    MaxFields
      | doc m%"
      A contract to check if a record only have a specific set of fields. This doesn't check the length of an inner record.

      # Example

      ```nickel multiline
      {foo = 1, bar = 1, baz = 1} | MaxFields 3

      {foo = 1, bar = 1, baz = 1} | MaxFields 2
      # => error: Record can't have more than `2` fields
      ```
      "%
      | std.number.Nat -> Dyn
      = fun propsCount =>
        std.contract.from_validator (fun value =>
          if std.typeof value != 'Record then
            'Error { message = "Expected a record, got %{std.to_string (std.typeof value)}" }
          else if std.record.length value > propsCount then
            'Error { message = "Record can't have more than `%{std.to_string propsCount}` fields" }
          else
            'Ok
        ),

    MinFields
      | doc m%"
      A contract to check if a record length is equal or greater than a specific legnth

      # Example

      ```nickel multiline
      {foo = 1, bar = 1, baz = 1} | MinFields 2

      {foo = 1, } | MinFields 2
      # => error: Record need at least `2` fields to be defined
      ```
        "%
      | std.number.Nat -> Dyn
      = fun propsCount =>
        std.contract.from_validator (fun value =>
          if std.typeof value != 'Record then
            'Error { message = "Expected a record, got %{std.to_string (std.typeof value)}" }
          else if std.record.length value < propsCount then
            'Error { message = "Record need at least `%{std.to_string propsCount}` fields to be defined" }
          else
            'Ok
        ),

    DependentFields
      | doc m%"
      A contract to assert the existence of fields when they are depdenent is defined in a value

      ```nickel multiline
      {first = 1, second = 2 } | DependentFields {first = ["second"]}

      {first = 1, } | DependentFields {first = ["second"]}
      # => error: Expected field `second`
      ```
    "%
      | { _ | Array String } -> Dyn
      = fun dependencies =>
        std.contract.from_validator (fun value =>
          if std.typeof value != 'Record then
            'Error { message = "Expected a record" }
          else
            let check_fields = fun fields record =>
              fields
              |> std.array.fold_right
                (fun e acc =>
                  if !std.record.has_field e record then
                    'Error { message = "Expected field `%{e}`" }
                  else
                    acc
                )
                'Ok
            in
            dependencies
            |> std.record.to_array
            |> std.array.fold_right
              (fun e acc =>
                if std.record.has_field e.field value then
                  check_fields e.value value
                  |> match {
                    'Ok => acc,
                    'Error err => 'Error (err & { notes = ["because field %{e.field} was present"] }),
                  }
                else
                  acc
              )
              'Ok
        ),
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
        "%
      = fun contract =>
        std.contract.custom (fun label value =>
          if std.typeof value != 'Record then
            'Error { message = "expected a record, got %{std.to_string (std.typeof value)}" }
          else
            std.record.to_array value
            |> std.array.try_fold_left
              (fun acc e =>
                std.contract.check contract."%{e.field}" label e.value
                |> match {
                  'Ok v => 'Ok { "%{e.field}" | contract."%{e.field}" = e.value } & acc,
                  'Error val => ('Error val),
                }
              )
              ('Ok {})
            |> match {
              'Ok _ => 'Ok value,
              'Error err => 'Error err,
            }
        ),

    RecordKeys
      | doc m%"
      Contract to strict record fields to a specific type

      # Example

      ```nickel multiline
      {"1" = 1, "2" = 2, "11" = 11 } | RecordKeys (std.string.Matches "^[0-9].*")

      {"1" = 1, "2" = 2, first = 1 } | RecordKeys (std.string.Matches "[0-9]")
      # => error: expected a string matching `[0-9]`
      ```
      "%
      | Dyn -> Dyn
      = fun contract =>
        std.contract.custom (fun label value =>
          if std.typeof value != 'Record then
            'Error { message = "Expected a record, got %{std.to_string (std.typeof value)}" }
          else
            std.record.to_array value
            |> std.array.try_fold_left
              (fun acc e =>
                std.contract.check contract label e.field
              )
              ('Ok value)
            |> match {
              'Ok _ => 'Ok value,
              'Error e => 'Error e,
            }
        ),

    JsonObject
      | doc m%"
          Represent a json record using standard json schema model for objects.
          Only use this when you want to code generation json schemas since most likely the code would look cleaner if you write your contract by hand.

          **NOTE**: Prefer using eager contracts over lazy ones.
        "%
      | { _ | { optional | Bool, contract | Dyn } } -> { _ | Dyn } -> Dyn -> Dyn
      = fun properties patternProperties additionalProperties =>
        std.contract.custom (fun label value =>
          let checked_pattern_properties =
            std.record.to_array value
            |> std.array.try_fold_left
              (fun acc e =>
                std.record.to_array patternProperties
                |> std.array.try_fold_left
                  (fun acc p =>
                    if std.string.is_match p.field e.field then
                      std.contract.check p.value label e.value
                      |> match {
                        'Ok val => 'Ok ({ "%{e.field}" | p.value = e.value } & acc),
                        'Error val => 'Error val
                      }
                    else
                      'Ok acc
                  )
                  acc
              )
              {}
          in

          let checked_properties =
            std.record.to_array properties
            |> std.array.try_fold_left
              (fun acc e =>
                if !std.record.has_field e.field value && !e.value.optional then
                  'Error { message = "Missing required field `%{e.field}`" }
                else if !std.record.has_field e.field value && e.value.optional then
                  # missing an optional propertie, nothing to do here
                  'Ok acc
                else
                  std.contract.check e.value.contract label value."%{e.field}"
                  |> match {
                    'Ok _ =>
                      let propertyContract = e.value.contract in
                      'Ok ({ "%{e.field}" | propertyContract = (value."%{e.field}") } & acc),
                    'Error e => 'Error e
                  }
              )
              {}
          in

          let partial_check =
            checked_pattern_properties
            & checked_properties
            |> std.enum.to_tag_and_arg
            |> std.record.get "arg"
          in
          let checked_additional_properties =
            std.record.to_array value
            |> std.array.try_fold_left
              (fun acc e =>
                if !std.record.has_field e.field partial_check then
                  std.contract.check additionalProperties label e.value
                  |> match {
                    'Ok _ =>
                      let additionalProperty = additionalProperties in
                      'Ok ({ "%{e.field}" | additionalProperty = e.value } & acc),
                    'Error e => 'Error e,
                  }
                else
                  'Ok acc
              )
              {}
          in

          let type = std.typeof (value | Dyn) in

          if type != 'Record then
            'Error { message = "expected a record, got `%{std.string.from_enum type}`", notes = [] }
          else
            [checked_properties, checked_pattern_properties, checked_additional_properties]
            |> match {
              ['Error e, _, _] => 'Error e,
              [_, 'Error e, _] => 'Error e,
              [_, _, 'Error e] => 'Error e,
              _ => checked_properties & checked_pattern_properties & checked_additional_properties,
            }
        ),

    get_value_at_path
      | doc m%"
    Retrieve a value from a record using an array of field names.

    # Example

    ```nickel multiline
    get_value_at_path ["first", "second", "third" ] { first = { second = { third = 3 } } }
    # => 'Found 3

    get_value_at_path ["magic"] { first = { second = { third = 3 } } }
    # => 'NotFound
    ```
    "%
      # : Array String -> { _ : Dyn } -> [| 'NotFound, 'Found |]
      = fun path value =>
        let leftOverPath = std.array.slice 1 (std.array.length path) path in
        let head = std.array.first path in

        std.typeof value
        |> match {
          'Array =>
            let is_number = std.string.is_match "^[0-9]+" head
            in
            if !is_number then
              std.fail_with "Value is an array but current path value is not an array index"
            else if is_number && std.array.length leftOverPath > 0 then
              get_value_at_path leftOverPath (std.array.at (std.string.to_number head) value)
            else
              'Found (std.array.at (std.string.to_number head) value),
          'Record =>
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
        },

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

    splitN
      | doc m%"
      Split a characeter N times and return the result as an array

      # Example

      ```nickel multiline
      splitN "this.will.split.twice" "." 2
      # => ["this", "will", "split.twice"]

      splitN "this.will.split.twice" "." 1
      # => ["this", "will.split.twice"]

      splitN "" "." 2
      # => [""]

      splitN "test" "." 1
      # => ["test"]

      splitN "v1.0" "." 1
      # => ["v1", "0" ]
      ```
     "%
      : String -> String -> Number -> Array String
      = fun s sep c =>
        let chars = std.string.characters s in
        let len = std.array.length chars in
        chars
        |> std.array.try_fold_left
          (fun acc e =>
            if acc.count == c then
              'Error acc
            else if e == sep then
              'Ok { result = acc.result @ [acc.intermediate], count = acc.count + 1, intermediate = "", index = acc.index + 1 }
            else
              'Ok { result = acc.result, count = acc.count, intermediate = acc.intermediate ++ e, index = acc.index + 1 }
          )
          { result = [], count = 0, intermediate = "", index = 0 }
        |> match {
          'Error r =>
            if r.result == [] then
              [s]
            else
              r.result @ [std.array.slice r.index len chars |> std.string.join ""],
          'Ok r =>
            if r.result == [] then
              [s]
            else
              r.result @ [std.array.slice r.index len chars |> std.string.join ""],
        },

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
      | doc m%"
        Contract for checking if an array has a specific length, min, max or both

        # Example

        ```nickel multiline
        [1, 2, 3, 4] | Length { max = 3 }
        # => error: Array doesn't satisfy the given constraints Min: 0, Max: 3

        [1] | Length { min = 2 }
        # => error: Array doesn't satisfy the given constraints Min: 2, Max: +inf

        [1,2,3] | Length { min = 2, max = 2 }
        # => error: Array doesn't satisfy the given constraints Min: 2, Max: 2
        ```
      "%
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
      | doc m%"
        A contract ensureing an array contains a specifc type with the specified minimum occurrance

        # Example

        ```nickel multiline
        [1, "first", "second"] | Contains { min = 2, } String

        [1, "first", "second"] | Contains { min = 3, } String
        # => error: Expecting at least 3 of the passed contract

        [1,2,3] | Contains { min =1, max = 2 } Number
        # => error: Expected at least 1 and at most 2 of the passed contract
        ```
      "%
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

            ```nickel multiline
            1234 | Port
            # => 1234

            500000 | Port
            # => error: contract broken by a value
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
        | doc m%"
        IPv4 address

        # Example

        ```nickel multiline
        123 | IPv4
        # => error: contract broken by a value

        "192.168.1.1" | IPv4

        "255.0.0.0.1" | IPv4
        # => error: contract broken by a value

        "256.0.0.0" | IPv4
        # => error: contract broken by a value
        ```
        "%
        =
          std.contract.from_validator (fun ip =>
            if std.typeof ip != 'String then
              'Error { message = "Expected string, got `%{std.typeof ip}`" }
            else
              let errMsg = 'Error { message = "Not a valid IPv4 address `%{ip}`" } in
              let parts = std.string.split "." ip in
              if std.array.length parts == 4 then
                parts
                |> std.array.try_fold_left
                  (fun acc val =>
                    let n = std.string.to_number val in
                    let starts_with_zero = fun n =>
                      let digits = std.string.characters n in
                      std.array.length digits > 1 && (digits |> std.array.at 0) == "0"
                    in
                    if std.string.is_match "^[0-9]+$" val && !starts_with_zero val && n >= 0 && n <= 255 then
                      'Ok ip
                    else
                      errMsg
                  )
                  null
                |> match {
                  'Ok _ => 'Ok,
                  'Error _ => errMsg,
                }
              else
                errMsg
          ),

      Hostname =
        std.contract.from_validator (fun name =>
          if std.typeof name != 'String then
            'Error { message = "Expected a string" }
          else if std.string.split "." name |> std.array.any (fun l => std.string.length l > 63) then
            'Error { message = "Hostname label can't be longer than 63 characters" }
          else if !std.string.is_match "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" name then
            'Error { message = "Hostname include invalid characters" }
          else
            'Ok
        ),
    },
}
