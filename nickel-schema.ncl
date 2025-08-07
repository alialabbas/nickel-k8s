let lib = import "lib.ncl" in
let ref_decode : String -> String = fun ref =>
  let encode_map = {
    "%22" = "\"",
    "%25" = "%",
    "~0" = "~",
    "~1" = "/",
  }
  in
  std.record.to_array encode_map
  |> std.array.fold_left
    (fun acc { field, value } =>
      std.string.replace field value acc
    )
    ref
in
let SchemaOptions
  | doc "Options to control certain behvaiors of the code generation notably doc generations and closing converted schemas contract by default"
  = {
    default_additional_properties
      | doc "simple flag to control the default schema bevaior, useful when generating many defintions and want to explicitly not allow the bad schema to accept more than it should like the k8 definitions"
      | Bool
      | default
      = true,
    lazy | Bool | optional,
    format_assertion | Bool | default = true,
  }
in

let rec is_complex = fun schema =>
  let is_array = std.record.has_field "type" schema && schema.type == 'array in
  let is_object = std.record.has_field "type" schema && schema.type == 'object in
  let is_object_properties_complex =
    std.array.try_fold_left
      (fun acc e =>
        if is_complex e.value then
          'Error true
        else
          'Ok false
      )
      false
      (std.record.to_array (std.record.get_or "properties" {} schema))
    |> match {
      'Ok v => v,
      'Error v => v,
    }
  in
  let is_additional_properties_complex =
    if std.record.has_field "additionalProperties" schema
    && std.typeof schema.additionalProperties != 'Bool then
      is_complex (std.record.get_or "additionalProperties" {} schema)
    else
      false
  in
  let is_pattern_properties_complex =
    std.array.try_fold_left
      (fun acc e =>
        if is_complex e.value then
          'Error true
        else
          'Ok false
      )
      false
      (std.record.to_array (std.record.get_or "patternProperties" {} schema))
    |> match {
      'Ok v => v,
      'Error v => v,
    }
  in
  let is_oneOf_complex =
    std.record.has_field "oneOf" schema
    && std.array.any
      (fun e =>
        (std.record.has_field "type" e && (e.type == "object" || e.type == "array"))
        || std.record.has_field "$ref" e
      )
      schema.oneOf
  in
  let is_anyOf_complex =
    std.record.has_field "anyOf" schema
    && std.array.any
      (fun e =>
        (std.record.has_field "type" e && (e.type == "object" || e.type == "array"))
        || std.record.has_field "$ref" e
      )
      schema.anyOf
  in
  if std.record.has_field "not" schema
  || is_oneOf_complex
  || std.record.has_field "allOf" schema
  || is_anyOf_complex then
    true
    # for arrays and object, we need to check the array type, properties, patternProperties and additionalPropertiesa respectively
  else if is_array then
    let items = std.record.get_or "items" {} schema in
    if std.typeof items == 'Bool then
      false
    else
      is_complex items
  else if is_object then
    is_object_properties_complex
    || is_additional_properties_complex
    || is_pattern_properties_complex
  else
    false
in
{

  IfThenElse
    | doc m%"
    Conditonal contract evaluated against then else when the if part fails. Otherwise, check it againsst the then part.

    ```nickel multiline
    12 | IfThenElse Number (lib.numbers.MultipleOf 2) String

    "test" | IfThenElse Number (lib.numbers.MultipleOf 2) String

    3 | IfThenElse Number (lib.numbers.MultipleOf 2) String
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

  int_handler | contract.NumberSchema -> Dyn = fun schema =>
    let multiple_of_contract =
      if std.record.has_field "multipleOf" schema then
        lib.numbers.MultipleOf schema.multipleOf
      else
        'None
    in

    let minimum_contract =
      let exclusive_minimum =
        let val = std.record.get_or "exclusiveMinimum" false schema in
        if std.typeof val == 'Number then
          true
        else
          val
      in
      let minimum =
        std.record.get_or
          "minimum"
          (
            if (std.record.get_or "exclusiveMinimum" null schema |> std.typeof) == '"Number" then
              schema.exclusiveMinimum
            else
              'None
          )
          schema
      in
      if minimum == 'None then
        'None
      else
        lib.numbers.MinRange minimum (!exclusive_minimum)
    in

    let maximum_contract =
      let exclusive_maximum =
        let val = std.record.get_or "exclusiveMaximum" false schema in
        if std.typeof val == 'Number then
          true
        else
          val
      in
      let maximum =
        std.record.get_or
          "maximum"
          (
            if (std.record.get_or "exclusiveMaximum" null schema |> std.typeof) == '"Number" then
              schema.exclusiveMaximum
            else
              'None
          )
          schema
      in
      if maximum == 'None then
        'None
      else
        lib.numbers.MaxRange maximum (!exclusive_maximum)
    in

    let base_type =
      schema.type
      |> match {
        'integer => std.number.Integer,
        'number => lib.contracts."Number",
      }
    in
    let all =
      [
        base_type,
        multiple_of_contract,
        minimum_contract,
        maximum_contract,
      ]
      |> std.array.filter (fun e => e != 'None)
    in
    std.contract.Sequence all,

  string_handler
    | contract.StringSchema -> Dyn
    = fun prop =>
      let min_len_contract =
        if std.record.has_field "minLength" prop then
          lib.strings.MinLength prop.minLength
        else
          'None
      in

      let max_len_contract =
        if std.record.has_field "maxLength" prop then
          lib.strings.MaxLength prop.maxLength
        else
          'None
      in

      let pattern =
        if std.record.has_field "pattern" prop then
          lib.strings.Regex prop.pattern
        else
          'None
      in

      let enum_contract =
        if std.record.has_field "enum" prop then
          std.array.fold_right
            (fun e acc => acc @ [e])
            []
            prop.enum
          |> lib.enum.ArrayEnum
        else
          'None
      in

      let type_contract =
        if std.record.has_field "format" prop then
          prop.format
          |> match {
            "uuid" => lib.contracts.UUID,
            "date-time" => lib.contracts.DateTime.DateTime,
            "date" => lib.contracts.DateTime.Date,
            "time" => lib.contracts.DateTime.Time,
            "duration" => lib.contracts.DateTime.Duration,
            "ipv4" => lib.networking.IPv4,
            "ipv6" => lib.networking.IPv6,
            "hostname" => lib.networking.Hostname,
            # TODO: implement the rest here
            _ => lib.contracts."String",
          }
        else
          lib.contracts."String"
      in
      let all =
        [
          String,
          type_contract,
          min_len_contract,
          max_len_contract,
          pattern,
          enum_contract
        ]
        |> std.array.filter (fun e => e != 'None)
      in

      std.contract.Sequence all,

  object_handler
    | doc m%"
        Generate a contract equivalent of a json schema. noLazy is a context to force the contract to be a non-lazy record evaluation
        This flag is necessary when we evaluate schemas inside of a oneOf subschema
      "%
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> contract.ObjectSchema -> Dyn
    = fun root converted options schema =>
      # Get additionalProperties and force it to be true or false only for the use of contract closure
      let isOpen = std.record.get_or "additionalProperties" options.default_additional_properties schema in
      # Default json schema behavior is to allow additional properties on missing properties
      let isOpen = if std.typeof isOpen == '"Bool" then isOpen else options.default_additional_properties in

      let additionalPropertiesSchema = std.record.get_or "additionalProperties" true schema in
      let additionalPropertiesSchema =
        if std.typeof additionalPropertiesSchema != '"Bool" then
          (json_schema_to_nickel root converted options schema.additionalProperties)
        else if isOpen then
          std.contract.from_predicate (fun _ => true)
        else
          std.FailWith "Record doesn't accept unspecified fields"
      in

      let patternPropertiesSchema = (
        schema.patternProperties
        |> std.record.to_array
        |> std.array.fold_right
          (fun e acc =>
            acc & { "%{e.field}" = (json_schema_to_nickel root converted options e.value) }
          )
          {}
      )
      in

      let propertiesSchema =
        (
          if schema.properties != {} then
            std.array.fold_right
              (fun e acc =>
                let isRequired = std.array.elem e.field schema.required in
                if isRequired then
                  acc & { "%{e.field}" | (json_schema_to_nickel root converted options e.value) }
                else
                  acc & { "%{e.field}" | (json_schema_to_nickel root converted options e.value) | optional }
              )
              {}
              (std.record.to_array schema.properties)
          else
            std.array.fold_right (fun e acc => acc & { "%{e}" | Dyn }) {} schema.required
        )
        |> (&) (if isOpen then { .. } else {})
      in

      let nonLazyProperties =
        if schema.properties != {} then
          std.array.fold_right
            (fun e acc =>
              let isRequired =
                if schema.required == [] then
                  false
                else
                  std.array.elem e.field schema.required
              in
              acc
              & {
                "%{e.field}" = {
                  contract = (json_schema_to_nickel root converted options e.value),
                  optional = (!isRequired)
                }
              }
            )
            {}
            (std.record.to_array schema.properties)
        else
          std.array.fold_right
            (fun e acc => acc & { "%{e}" = { contract = Dyn, optional = false, } })
            {}
            schema.required
      in

      let dependentContract =
        if schema.dependentRequired != {} then
          lib.records.DependentFields schema.dependentRequired
        else
          Dyn
      in

      let minProperties =
        if std.record.has_field "minProperties" schema then
          lib.records.MinFields schema.minProperties
        else
          Dyn
      in

      let maxProperties =
        if std.record.has_field "maxProperties" schema then
          lib.records.MaxFields schema.maxProperties
        else
          Dyn
      in

      let property_names_contract =
        if std.record.has_field "propertyNames" schema then
          lib.records.RecordKeys (json_schema_to_nickel root converted schema.propertyNames)
        else
          Dyn
      in

      schema
      |> match {
        # NOTE: required here is the result of the object schema contract
        # First match only a single type of prperties
        {
          additionalProperties,
          ..rest
        } if schema.properties == {}
          && schema.patternProperties == {}
          && schema.required == [] =>
          if options.lazy then
            { _ | additionalPropertiesSchema }
          else
            lib.records.JsonObject {} {} additionalPropertiesSchema,
        {
          properties,
          ..rest
        } if (!std.record.has_field "additionalProperties" schema || (std.record.has_field "additionalProperties" schema && std.typeof schema.additionalProperties == 'Bool))
          && schema.patternProperties == {}
          && options.lazy => propertiesSchema,
        _ =>
          std.contract.Sequence [
            lib.records.JsonObject nonLazyProperties patternPropertiesSchema additionalPropertiesSchema,
            dependentContract,
            minProperties,
            maxProperties,
            property_names_contract
          ],
      },

  array_handler
    | doc m%"
    Convert a schema containing array keywords into a Nickel Contract
    ```
    "%
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> contract.ArraySchema -> Dyn
    = fun root converted options schema =>
      # TODO: when prefix items is present, we will need to allow the first few values
      # then only when we skipp the prefixes, we check against the false/true schema
      # We might need to make either Array Something or TupleContract
      # This is what is causing the issue, mixing the two doesn't make sense since the tuple always have to check the rest of teh contract
      let array_elem =
        if std.record.has_field "items" schema then
          let items = std.typeof (std.record.get "items" schema) in
          items
          |> match {
            'Bool => json_schema_to_nickel root {} options schema.items,
            '"Record" => json_schema_to_nickel root converted options schema.items,
          }
        else
          json_schema_to_nickel root {} options true
      in

      let array_contract = if options.lazy then Array array_elem else lib.contracts.ArrayOf array_elem in

      let array_length =
        let range =
          {
            min = std.record.get_or "minItems" null schema,
            max = std.record.get_or "maxItems" null schema
          }
          |> std.record.filter (fun k v => v != null)
        in
        range
        |> match {
          { min, } => lib.arrays.Length { include min },
          { max, } => lib.arrays.Length { include max },
          { min, max } => lib.arrays.Length { include min, include max },
          {} => 'None, # TODO: Is this safe to assume
        }
      in

      let set_contract =
        let hasSetFlag = std.record.get_or "uniqueItems" false schema in
        if hasSetFlag then
          lib.arrays.IsSet
        else
          'None
      in
      # TODO: tuple type won't work without special handling
      let tuple_contract =
        let tupleType =
          std.record.get_or "items" true schema
          |> match {
            false => 'Exact,
            true => ('AdditionalItems Dyn),
            { ..rest } => 'AdditionalItems (json_schema_to_nickel root converted options schema.items),
          }
        in
        if std.record.has_field "prefixItems" schema then
          let prefix =
            std.array.fold_right
              (fun subSchema acc => [(json_schema_to_nickel root converted options subSchema)] @ acc)
              []
              schema.prefixItems
            |> lib.arrays.Tuple
          in
          prefix tupleType
        else
          'None
      in

      let contains_contract =
        if std.record.has_field "contains" schema then
          let minCount = std.record.get_or "minContains" 1 schema in
          let maxCount = if std.record.has_field "maxContains" schema then { max = schema.maxContains } else {} in
          let ContainsContract = (json_schema_to_nickel root converted options schema.contains) in
          lib.arrays.Contains ({ min = minCount } & maxCount) ContainsContract
        else
          'None
      in

      let contract = if std.record.has_field "prefixItems" schema then tuple_contract else array_contract in

      let all =
        [
          # TODO: every contract we expect to use here should have an array check
          contract,
          array_length,
          set_contract,
          contains_contract,
        ]
        |> std.array.filter (fun e => e != 'None)
      in
      std.contract.Sequence all,

  one_of_handler
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> Array contract.JsonSchema -> Dyn
    = fun root converted options schema =>
      std.array.fold_right
        (fun e acc => acc @ [(json_schema_to_nickel root converted options e)])
        []
        schema
      |> lib.contracts.OneOf,

  any_of_handler
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> Array contract.JsonSchema -> Dyn
    = fun root converted options schema =>
      std.array.fold_right
        (fun e acc => acc @ [(json_schema_to_nickel root converted options e)])
        []
        schema
      |> lib.contracts.AnyOf,

  all_of_handler
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> Array contract.JsonSchema -> Dyn
    = fun root converted options schema =>
      std.array.fold_right
        (fun e acc => acc @ [(json_schema_to_nickel root converted options e)])
        []
        schema
      |> std.contract.all_of,

  enum_handler | Array Dyn -> Dyn = fun schema =>
    std.array.fold_right
      (fun e acc => acc @ [e])
      []
      schema
    |> lib.enum.ArrayEnum,

  schema_to_nickel
    | doc m%"
    Generate a Custom Nickel contract ouf of a json schema for evaluation at runtime.

    ```nickel multiline
    1 | (schema_to_nickel {} {type = "number", maximum = 10 })
    # => 1

    500000 | (schema_to_nickel {} {type = "number", maximum = 10 })
    # => error: contract broken by a value

    { }
      | (
        schema_to_nickel {} {
          type = "object",
          properties = { first = { type = "string" } },
          required = ["first"],
        }
      )
    # => error: missing definition for `first`
    ```
  "%
    | SchemaOptions -> contract.JsonSchema -> Dyn
    = fun options schema =>
      let _schema = schema in
      let options = if std.record.has_field "lazy" options then options else options & { lazy | force = !is_complex schema } in
      json_schema_to_nickel _schema {} options _schema,

  json_schema_to_nickel
    | doc m%"
      Convert a json schema to a nickel string that can be exported using `nickel export -f raw`.
      `lazy` controls the type of contracts generated for Records. By design those are lazy and in some cases like in allOf and OneOf expressions
      reocrds need to be non-lazy to be able to check if the a schema predicate is satisfied or not.
      Passing a false will force all records to be non-lazy including simple ones that could be represented as a simple nickel record contract.
    "%
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> contract.JsonSchema -> Dyn
    = fun root converted options schema =>
      if std.typeof schema == 'Bool then
        let _schema = schema in
        std.contract.from_predicate (fun _ => _schema)
      else
        let oneOf =
          if std.record.has_field "oneOf" schema then
            (one_of_handler root converted options schema.oneOf)
          else
            'None
        in

        let allOf =
          if std.record.has_field "allOf" schema then
            (all_of_handler root converted options schema.allOf)
          else
            'None
        in

        let anyOf =
          if std.record.has_field "anyOf" schema then
            (any_of_handler root converted options schema.anyOf)
          else
            'None
        in

        let not =
          if std.record.has_field "not" schema then
            std.contract.not (json_schema_to_nickel root converted options schema.not)
          else
            'None
        in

        let ref =
          if std.record.has_field "$ref" schema then
            ref_handler root converted options schema."$ref"
          else
            'None
        in

        let conditionalIf =
          if std.record.has_field "if" schema then
            let ef = schema."if" in
            let ef = (json_schema_to_nickel root converted options ef) in

            let zen = std.record.get_or "then" {} schema in
            let zen = (json_schema_to_nickel root converted options zen) in

            let els = std.record.get_or "else" {} schema in
            let els = (json_schema_to_nickel root converted options els) in
            IfThenElse ef zen els
          else
            'None
        in

        let contract = (
          let json_dynamic = [
            # TODO: probably the object here need to be non-lazy in case we need to evaluate its full graph
            (object_handler root converted options schema),
            (array_handler root converted options schema),
            (string_handler schema),
            (int_handler schema),
            lib.contracts."Bool",
            # TODO: extract this out
            (
              std.contract.custom (fun label value =>
                if value == null then
                  'Ok value
                else
                  'Error { message = "Expected a null" }
              )
            ),
          ]
          in
          let json_dynamic =
            if ref != 'None then
              # std.contract.Sequence [lib.contracts.AnyOf json_dynamic, ref]
              # TODO: this, how do handle this?
              ref
            else
              lib.contracts.AnyOf json_dynamic
          in
          # Remove the composition keywords to make it easier to work with this schema type
          let schema =
            std.array.fold_right
              (fun e acc =>
                if std.record.has_field e acc then
                  std.record.remove e acc
                else
                  acc
              )
              schema
              (std.record.fields_with_opts contract.SchemaComposition)
          in
          schema
          |> match {
            {} => contract.Any,
            # Represent a multi-type schema as an AnyOf Contract
            # TODO: probably could just use one_of_hander instead of handwiring this ourselves
            { ..rest } if std.record.has_field "type" rest && std.typeof rest.type == 'Array =>
              (
                std.array.fold_right
                  (fun e acc => acc @ [(json_schema_to_nickel root converted options (rest & { type | force = e }))])
                  []
                  rest.type
                |> lib.contracts.OneOf
              ),
            { type = 'string, enum, ..rest } => string_handler schema,
            { enum, ..rest } => enum_handler enum,
            { const, ..rest } => lib.contracts.Equal const,
            { type = 'string, ..rest } => string_handler schema,
            { type = 'number, ..rest } => int_handler schema,
            { type = 'integer, ..rest } => int_handler schema,
            { type = 'boolean, ..rest } => lib.contracts."Bool",
            { type = 'array, ..rest } => array_handler root converted options schema,
            { type = 'object, ..rest } => object_handler root converted options schema,
            { type = 'null, ..rest } => std.contract.from_predicate (fun val => val == null),
            _ => json_dynamic,
          }
        )
        in
        # TOOD: all methods should yield back a 'None or 'Ok contract
        let convertedSchema = (std.array.filter (fun e => e != 'None) [contract, oneOf, anyOf, allOf, not, conditionalIf]) in
        let convertedSchema =
          if std.array.length convertedSchema == 1 then
            std.array.first convertedSchema
          else
            std.contract.Sequence convertedSchema
        in
        convertedSchema,

  # TODO: still need to handle achor refs and id refs
  # https://json-schema.org/understanding-json-schema/structuring#retrieval-uri
  ref_handler
    | contract.JsonSchema -> { _ | Dyn } -> SchemaOptions -> String -> Dyn
    | default
    = fun root converted options ref =>
      if std.record.has_field ref converted then
        std.trace "From Cache: %{ref}" converted."%{ref}"
      else
        let path = std.string.split "/" ref in
        # need to remove `#`, for now we are always assuming working on root doc
        path
        |> match {
          ["#"] => (json_schema_to_nickel root converted options root),
          arr if std.array.length arr == 1 => std.FailWith "Can't compute ids or remote references `%{ref}`",
          _ =>
            let path = std.array.slice 1 (std.array.length path) path in
            let path = path |> std.array.map (fun e => ref_decode e) in
            lib.records.get_value_at_path path root
            |> match {
              'Found ref_schema => (json_schema_to_nickel root converted options ref_schema),
              'NotFound => std.FailWith "Failed to evaluete ref `%{ref}`",
            }
        },

  openapi_nickel = fun api_doc =>
    let lazy = !(is_complex api_doc) in
    let defs = if std.record.has_field "swagger" api_doc then std.record.get_or "definitions" {} api_doc else api_doc.components.schemas in
    std.array.fold_right
      (fun e acc =>
        let contract = json_schema_to_nickel api_doc {} { include lazy, default_additional_properties = false, } e.value in
        acc
        & { "%{e.field}" = contract, }
      )
      {}
      (std.record.to_array defs),

  Schema
    | doc m%"
    A contract to check if a record is a valid json schema

    ```nickel multiline
    {} | Schema

    {type = "number"} | Schema

    {type = ["number", "string"]} | Schema

    { type = "random" } | Schema
    # => error: tag not in the enum type
    ```
  "%
    = contract.JsonSchema,

  contract = {
    # TODO: exclusiveX when Boolean should only be allowed when there is a min or max,
    NumberSchema = {
      type | std.enum.TagOrString | [| 'number, 'integer, |] | default = "number",
      minimum | Number | optional,
      maximum | Number | optional,
      exclusiveMaximum | std.contract.any_of [ Number, Bool ] | optional,
      exclusiveMinimum | std.contract.any_of [ Number, Bool ] | optional,
      multipleOf | Number | optional,
      markdownDescription | String | default = "",
      description | String | default = "",
      .. # We are always allowing more than usual since we want to allow custom definitions like kube to work
    },

    # TODO: figure out defaults here and how it works out with the main recursive method
    # having to check betweel all of these types is a bit annoying
    ArraySchema = {
      type | String | force = "array",
      items | JsonSchema | optional,
      prefixItems | Array JsonSchema | optional,
      contains | JsonSchema | optional,
      minContains | std.number.Nat | optional,
      maxContains | std.number.Nat | optional,
      minItems | std.number.Nat | optional,
      maxItems | std.number.PosNat | optional,
      uniqueItems | Bool | optional,
      # TODO: implement me, probably would require returning the indexes of non-evaluted properties
      # if we are not checking, the contract ends
      # otherwise we continue to check
      unevaluatedItems | JsonSchema | optional,
      ..
    },

    StringSchema = {
      # type = "string",
      minLength | std.number.PosNat | optional,
      maxLength | std.number.PosNat | optional,
      pattern | String | optional,
      format | String | optional,
      ..
    },

    # TODO: is it possible to type PosNatad of contract check, benefit of a contract is playing with the fields without changing the underlying type
    ObjectSchema = {
      required | Array String | default = [],
      type = "object",
      description | String | default = "",
      # TODO: Technically what is inside is a schema, if we can capture that, that would make the code better
      properties | { _ | JsonSchema } | default = {},
      patternProperties | { _ | JsonSchema } | default = {},
      # TODO: this need special contract, bool or schema
      additionalProperties | Dyn | optional,
      # TODO: this work with subschemas, so we need to know what
      unevaluatedProperties | JsonSchema | default = true,
      # These are easy to implement
      propertyNames | JsonSchema | optional,
      minProperties | std.number.Nat | optional,
      maxProperties | std.number.Nat | optional,
      dependentRequired | { _ | Array String } | default = {},
      ..
    },

    SchemaComposition = {
      oneOf | Array JsonSchema | optional,
      anyOf | Array JsonSchema | optional,
      allOf | Array JsonSchema | optional,
      not | JsonSchema | optional,
      ..
    },
    JsonSchema =
      let SchemaType =
        std.contract.custom (fun label value =>
          let _types = [|
            'number,
            'integer,
            'array,
            'string,
            'object,
            'boolean,
            'null
          |]
          in
          std.typeof value
          |> match {
            'Array => 'Ok (value | Array (lib.enum.StringOrEnum _types) | lib.arrays.IsSet),
            'String => 'Ok (value | std.enum.TagOrString | _types),
            'Enum => 'Ok (value | _types),
            _ =>
              'Error {
                message = "Expected either an array or string, got %{std.to_string (std.typeof value)}"
              }
          }
        )
      in
      let CoreSchema =
        {
          type | SchemaType | optional,
          default | Any | optional,
          definitions | { _ | JsonSchema } | optional,
          "$ref" | String | optional,
          "$schema" | String | optional,
          "$id" | String | optional,
          "$comment" | String | optional,
          "$defs" | { _ | JsonSchema } | optional,
          title | String | optional,
          markdownDescription | String | optional,

          enum | Array Any | optional,
          const | Any | optional,
          description | String | optional,

          # Integer/Number Props
          minimum | Number | optional,
          maximum | Number | optional,
          exclusiveMaximum | std.contract.any_of [ Number, Bool ] | optional,
          exclusiveMinimum | std.contract.any_of [ Number, Bool ] | optional,
          multipleOf | Number | optional,

          # Array Props
          items | JsonSchema | optional,
          prefixItems | Array JsonSchema | optional, # Schema contract please
          contains | JsonSchema | optional,
          minContains | std.number.Nat | optional,
          maxContains | std.number.Nat | optional,
          minItems | std.number.Nat | optional,
          maxItems | std.number.PosNat | optional,
          uniqueItems | Bool | optional,

          # String Props
          minLength | std.number.PosNat | optional,
          maxLength | std.number.PosNat | optional,
          pattern | String | optional,
          format | String | optional,

          # Object Props
          required | Array String | optional,
          properties | { _ | JsonSchema } | optional,
          patternProperties | { _ | JsonSchema } | optional,
          additionalProperties | JsonSchema | optional,

          # if else then schema
          "if" | JsonSchema | optional,
          "then" | JsonSchema | optional,
          "else" | JsonSchema | optional,

          # Extensions are not validated but we want to keep them
          ..
        }
        & SchemaComposition
      in
      std.contract.custom (fun label schema =>
        std.typeof schema
        |> match {
          'Bool => 'Ok schema,
          'Record => 'Ok (schema | CoreSchema),
          t => 'Error { message = "Invalid JsonSchema type, expected a record or a bool. Got %{std.to_string t}" }
        }
      ),

    Never = std.FailWith "`false` schema always fail validation",
    Any =
      std.contract.from_validator (fun v =>
        if v == null then
          'Ok
        else
          let type = std.typeof v in
          type
          |> match {
            'Record => 'Ok,
            'Array => 'Ok,
            'String => 'Ok,
            'Number => 'Ok,
            'Bool => 'Ok,
            _ => 'Error { "Invalid json type %{std.to_string type}" },
          }
      ),
  }
}
