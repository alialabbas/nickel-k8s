let lib = import "lib.ncl" in
let Nullable
  | doc "Apply the Contract to an array and allow it to also be assigned as null"
  = fun contract =>
    std.contract.custom (fun label value =>
      if value == null then
        'Ok null
      else
        std.contract.check (contract) label value
    )
in
let Any =
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
  )
in
let JsonAny =
  std.contract.from_validator (fun v =>
    std.typeof v
    |> match {
      'Record => 'Ok,
      'Bool => 'Ok,
      'String => 'Ok,
      'Number => 'Ok,
      'Array => 'Ok,
      _ =>
        'Error {
          message = "Nickel type %{std.to_string(std.typeof v)} is not a valid json type",
        }
    }
  )
in
let rec JsonSchema =
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
  let CoreSchema = {
    type
      | SchemaType
      | optional,
    default | JsonAny | optional,
    definitions | { _ | JsonSchema } | optional,
    "$ref" | String | optional,
    "$schema" | String | optional,
    "$id" | String | optional,
    "$comment" | String | optional,
    title | String | optional,
    markdownDescription | String | optional,

    enum | Array Any | optional,
    const | JsonAny | optional,
    description | String | optional,

    # Integer/Number Props
    minimum | Nullable Number | optional,
    maximum | Nullable Number | optional,
    exclusiveMaximum | std.contract.any_of [ Number, Bool ] | optional,
    exclusiveMinimum | std.contract.any_of [ Number, Bool ] | optional,
    multipleOf | Number | optional,

    # Array Props
    items | std.contract.any_of [ Bool, JsonSchema] | optional,
    prefixItems | Array JsonSchema | optional, # Schema contract please
    contains | JsonSchema | optional,
    minContains | std.number.PosNat | optional,
    maxContains | std.number.PosNat | optional,
    minItems | std.number.Nat | optional,
    maxItems | std.number.PosNat | optional,
    uniqueItems | Bool | optional,

    # String Props
    minLength | std.number.PosNat | optional,
    maxLength | std.number.PosNat | optional,
    pattern | String | optional,
    # TODO: format is abused by json schemas, convert this to just a a simple array check
    # TODO: this should also somehow be extensible to allow string extension handling based on what the user of the lib wants to do
    format
      | std.enum.TagOrString
      | [|
        'date-time,
        'time,
        'date,
        'duration,
        'email,
        'idn-hostname,
        'ipv4,
        'ipv6,
        'uuid,
        'uri,
        'uri-reference,
        'iri,
        'iri-referemce,
        'uri-template,
        'json-pointer,
        'relative-json-pointer,
        'regex,
        'uint64,
        'int64,
        'int32,
        'byte,
        'binary,
        'string,
        'url,
        'int-or-string,
        'double,
      |]
      | optional,

    # Object Props
    required | Array String | optional,
    properties | { _ | JsonSchema } | optional,
    patternProperties | { _ | JsonSchema } | optional,
    additionalProperties | std.contract.any_of [ Bool, JsonSchema] | optional,

    oneOf | Array JsonSchema | optional,
    anyOf | Array JsonSchema | optional,
    allOf | Array JsonSchema | optional,
    not | JsonSchema | optional,
    ..
  }
  in
  # PERF: this is introducing almost a 2s processing
  # I suspect this is due nickel not optimizing anything inside of this contract when it comes to fetch the CoreSchema keywords and most likely needs to be scoped out
  let ExtensionKeywordCheck =
    std.contract.custom (fun label value =>
      let schema_keywords = std.record.fields_with_opts CoreSchema in
      let extension_keys =
        std.record.fields value
        |> std.array.filter (fun e => !(std.array.elem e schema_keywords))
      in
      let result =
        extension_keys
        |> std.array.fold_right
          (fun e acc =>
            if !std.string.is_match "x-.*" e then
              acc @ ["`%{e}`"]
            else
              acc
          )
          []
      in
      if result == [] then
        'Ok value
      else
        'Error { message = "Schema has invalid keyword", notes = result }
    )
  in
  CoreSchema
# std.contract.all_of [CoreSchema, ExtensionKeywordCheck]
in
let Schemas = {
  # TODO: exclusiveX when Boolean should only be allowed when there is a min or max,
  NumberSchema = {
    type | std.enum.TagOrString | [| 'number, 'integer, |] | default = "number",
    minimum | Nullable Number | optional,
    maximum | Nullable Number | optional,
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
    items | std.contract.any_of [ Bool, JsonSchema] | optional,
    prefixItems | Array JsonSchema | optional,
    contains | { .. } | optional,
    minContains | std.number.PosNat | optional,
    maxContains | std.number.PosNat | optional,
    minItems | std.number.Nat | optional,
    maxItems | std.number.PosNat | optional,
    uniqueItems | Bool | optional,
    ..
  },

  StringSchema = {
    type = "string",
    minLength | std.number.PosNat | optional,
    maxLength | std.number.PosNat | optional,
    pattern | String | optional,
    # TODO: format is abused by json schemas, convert this to just a a simple array check
    format
      | std.enum.TagOrString
      | [|
        'date-time,
        'time,
        'date,
        'duration,
        'email,
        'idn-hostname,
        'ipv4,
        'ipv6,
        'uuid,
        'uri,
        'uri-reference,
        'iri,
        'iri-referemce,
        'uri-template,
        'json-pointer,
        'relative-json-pointer,
        'regex,
        'uint64,
        'int64,
        'int32,
        'byte,
        'binary,
        'string,
        'url,
        'int-or-string
      |]
      | optional,
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
    ..
  },
}
in

let Converters = {
  # TODO: in an ideal world we would have some sort of map to keep track of what contracts to generate as a non lazy version of themselves to allow us to just produce non-lazy on the required set and nothing else
  # TODO: some bad schemas might have a oneOf with a singular array that might be better off optimized as a singular contract rather than a boolean expression. This means, we might need to do inline transformation for such a thing to be able to avoid non-lazy contracts as much as possible.
  # TODO: technically speaking, the only contract that we can't keep in check between lazy and non-lazy is the the record one. So we could technically introspect the schema further to only generated the non-lazy one when the underlying condition of a property is OneOf and so on.
  # TODO: need a check for the internals of an object, i.e.... Only if there is multiple objects or objects with properties do we truly want to be non-lazy
  # TODO: OneOf and AnyOf is solvable if only a single schema is a record, only an issue when we compare multiple objects
  # TODO: AllOf: Since the code is generated at runtime, if we know all the instances are objects, we could just generate their contracts or even better merge them, all of anyway is a merge of all, can always just be treated like that and minimize what's going on under the hood
  # TODO: Not can work for simple objects and has to be closed, any open record would just fail
  is_complex | JsonSchema -> Bool = fun schema =>
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
          # TODO: same thing for other combinators and also think about a way to also evaluate $ref somehow
          || std.record.has_field "$ref" e
        )
        schema.oneOf
    in
    if std.record.has_field "not" schema
    || is_oneOf_complex
    # || std.record.has_field "oneOf" schema
    || std.record.has_field "allOf" schema
    || std.record.has_field "anyOf" schema then
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
      false,

  int_handler | Schemas.NumberSchema -> Dyn = fun schema =>
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
    | Schemas.StringSchema -> Dyn
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
            'uuid => lib.contracts.UUID,
            'date-time => lib.contracts.DateTime.DateTime,
            'date => lib.contracts.DateTime.Date,
            'time => lib.contracts.DateTime.Time,
            'duration => lib.contracts.DateTime.Duration,
            'ipv4 => lib.networking.IPv4,
            'ipv6 => lib.networking.IPv6,
            # TODO: implement the rest here
            _ => lib.contracts."String",
          }
        else
          lib.contracts."String"
      in
      let all =
        [
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
    | Schemas.ObjectSchema -> Dyn -> Dyn -> Bool -> Dyn
    = fun schema converted definitions lazy =>
      # Get additionalProperties and force it to be true or false only for the use of contracct closure
      let isOpen = std.record.get_or "additionalProperties" options.default_additional_properties schema in
      # Default json schema behavior is to allow additional properties on missing properties
      let isOpen = if std.typeof isOpen == '"Bool" then isOpen else options.default_additional_properties in

      let additionalPropertiesSchema = std.record.get_or "additionalProperties" true schema in
      let additionalPropertiesSchema =
        if std.typeof additionalPropertiesSchema != '"Bool" then
          (json_schema_to_nickel schema.additionalProperties converted definitions lazy).schema
        else
          isOpen
      in

      let patternPropertiesSchema = (
        schema.patternProperties
        |> std.record.to_array
        |> std.array.fold_right
          (fun e acc =>
            acc & { "%{e.field}" = (json_schema_to_nickel e.value converted definitions lazy).schema }
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
                  acc & { "%{e.field}" | (json_schema_to_nickel e.value converted definitions lazy).schema }
                else
                  acc & { "%{e.field}" | (json_schema_to_nickel e.value converted definitions lazy).schema | optional }
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
                  contract = (json_schema_to_nickel e.value converted definitions lazy).schema,
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
          if lazy then
            { _ | additionalPropertiesSchema }
          else
            lib.records.JsonObject {} {} additionalPropertiesSchema,
        {
          properties,
          ..rest
        }
        # TODO: this probably should be here as long as additional properties is bool
        # TODO: remove this oneOf condition later on
        # TODO: maybe making these lazy is not worthwhile right now.... % operator on record contracts is no different than chaining them
        if (!std.record.has_field "additionalProperties" schema || (std.record.has_field "additionalProperties" schema && std.typeof schema.additionalProperties == 'Bool))
          && schema.patternProperties == {}
          && lazy => propertiesSchema,
        _ => (lib.records.JsonObject nonLazyProperties patternPropertiesSchema additionalPropertiesSchema)
      },

  array_handler | Schemas.ArraySchema -> Dyn -> Dyn -> Bool -> Dyn = fun schema converted definitions lazy =>
    let array_elem =
      if std.record.has_field "items" schema then
        # TODO: This should check if items exist
        let items = std.typeof (std.record.get "items" schema) in
        items
        |> match {
          # TODO: when does this make sense?
          # This is only meaningful when we are validating prefixItems and want to capture it
          'Bool => (json_schema_to_nickel {} {} {} false).schema,
          # TODO: what happens with arrays in a lazy schema
          # well, it is just an array, it could have a schema but we odn't care about it beyond that.
          # it just means we won't be able to evaluate it in a is_contract test which just breaks testability. Although that's just for testing correctness
          # other parts should be the same as well. The array could be inlined inside of a oneOf and such, and that's when it would need to be checked
          '"Record" => (json_schema_to_nickel schema.items converted definitions lazy).schema,
        }
      else
        (json_schema_to_nickel {} {} {} false).schema
    in

    let array_contract = if lazy then Array array_elem else lib.contracts.ArrayOf array_elem in

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
        { min, } => let _min = min in lib.arrays.Length { min = _min },
        { max, } => let _max = max in lib.arrays.Length { max = _max },
        { min, max } => lib.arrays.Length { min = min, max = max },
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
          { ..rest } => 'AdditionalItems (json_schema_to_nickel schema.items converted definitions false).schema,
        }
      in
      if std.record.has_field "prefixItems" schema then
        let prefix =
          std.array.fold_right
            (fun subSchema acc => [(json_schema_to_nickel subSchema converted definitions false).schema] @ acc)
            []
            schema.prefixItems
          |> lib.arrays.Tuple
        in
        prefix tupleType
      else
        'None
    in

    let all =
      [
        array_contract,
        array_length,
        tuple_contract,
        set_contract
      ]
      |> std.array.filter (fun e => e != 'None)
    in
    std.contract.Sequence all,

  options
    | doc "Options to control certain behvaiors of the code generation notably doc generations and closing converted schemas contract by default"
    = {
      include_docs
        | doc m%"
        Whether to include docs in the generated records.
        NOTE: this is only used when it makes sense, in non-lazy records docs are completely ignored.
      "%
        | Bool
        | default
        = true,
      default_additional_properties
        | doc "simple flag to control the default schema bevaior, useful when generating many defintions and want to explicitly not allow the bad schema to accept more than it should like the k8 definitions"
        | Bool
        | default
        = false, # TODO: this need to be properly supplied as option parameter to the converter
    },

  # NOTE: contract defaulted method to allow customization by external user if they want to handle it differently, this now is done only for k8s
  # TODO: Expirement with a toggle to control the prefix for generation. This could be useful

  one_of_handler | Array JsonSchema -> Dyn -> Dyn -> Dyn = fun schema converted definitions =>
    std.array.fold_right
      (fun e acc => acc @ [(json_schema_to_nickel e converted definitions false).schema])
      []
      schema
    |> lib.contracts.OneOf,

  any_of_handler | Array JsonSchema -> Dyn -> Dyn = fun schema converted definitions =>
    std.array.fold_right
      (fun e acc => acc @ [(json_schema_to_nickel e converted definitions false).schema])
      []
      schema
    |> lib.contracts.AnyOf,

  all_of_handler | Array JsonSchema -> Dyn -> Dyn = fun schema converted definitions =>
    std.array.fold_right
      (fun e acc => acc @ [(json_schema_to_nickel e converted definitions false).schema])
      []
      schema
    |> std.contract.all_of,

  enum_handler | Array Dyn -> Dyn = fun schema =>
    std.array.fold_right
      (fun e acc => acc @ [e])
      []
      schema
    |> lib.enum.ArrayEnum,

  # TODO: the non-lazy and lazy should be equivelant when not using oneOf and such
  # This happens in the basic kube crd stuff
  # TODO: the helper method could keep a ref to pass around for definitions to be used from $ref possible nodes
  # in theory, this should speed up compuation a lot since we will be avoiding so many unncessary ref compuatations
  schema_to_nickel
    | JsonSchema -> Dyn
    = fun schema =>
      let definitions = std.record.get_or "definitions" {} schema in
      let def_complex =
        std.array.try_fold_left
          (fun acc e =>
            if is_complex e.value then
              'Error true
            else
              'Ok false
          )
          null
          (std.record.to_array definitions)
        |> match { 'Error _ => true, 'Ok _ => false }
      in
      # TODO: this is another gotcha,
      let lazy = !(is_complex schema) && !def_complex in
      let _definitions =
        std.record.to_array definitions
        |> std.array.fold_right
          (fun e acc =>
            if std.record.has_field e.field acc then
              std.trace "Skipping outside %{e.field}" (std.test.Assert (std.record.has_field e.field acc))
            else
              let result = (json_schema_to_nickel e.value acc definitions lazy) in
              let acc =
                std.record.to_array result.defs
                |> std.array.fold_right
                  (fun e _acc =>
                    if std.record.has_field e.field _acc then
                      _acc
                    else
                      _acc & { "%{e.field}" = e.value }
                  )
                  acc
              in
              acc & { "%{e.field}" = result.schema }
          )
          {}
      in
      let _schema = schema in
      { schema = (json_schema_to_nickel _schema _definitions definitions lazy).schema, defs = _definitions },

  # TODO: laziness is a bitch
  # basically, if we are lazy, then we don't care about anything other than the basic contract
  # all boolean condition don't exist and basically can just wrap a single basic contract back
  json_schema_to_nickel
    | doc m%"
      Convert a json schema to a nickel string that can be exported using `nickel export -f raw`.
      `lazy` controls the type of contracts generated for Records. By design those are lazy and in some cases like in allOf and OneOf expressions
      reocrds need to be non-lazy to be able to check if the a schema predicate is satisfied or not.
      Passing a false will force all records to be non-lazy including simple ones that could be represented as a simple nickel record contract.
    "%
    | JsonSchema -> { _ | Dyn } -> { _ | JsonSchema } -> Bool -> { schema | Dyn, defs | { _ | Dyn } }
    = fun schema converted definitions lazy =>
      let oneOf =
        if std.record.has_field "oneOf" schema then
          (one_of_handler schema.oneOf converted definitions)
        else
          'None
      in

      let allOf =
        if std.record.has_field "allOf" schema then
          (all_of_handler schema.allOf converted definitions)
        else
          'None
      in

      let anyOf =
        if std.record.has_field "anyOf" schema then
          (any_of_handler schema.anyOf converted definitions)
        else
          'None
      in

      let not =
        if std.record.has_field "not" schema then
          std.contract.not (json_schema_to_nickel schema.not converted definitions lazy).schema
        else
          'None
      in

      # TODO: how to evaluate this once when ref is used in multiple places?
      # here we inside of a stack, the value of the ref needs to be extracted out and added.
      # One mean is to constantly push back a value of the evaluated refs from within the evaluation to allow us to constantly add them to the root as it traverse the nodes
      # this should in theory optimize a bit to avoid uncessary compuation, let's see how fast this would improve compuations
      let ref =
        if std.record.has_field "$ref" schema then
          ref_handler converted definitions schema."$ref" lazy
        else
          'None
      in

      # TODO: this will always be json dynamic non-lazy when there is only $ref
      # Need a way to only load this if and only if the rest has something sensible
      let contract = (
        # TODO: technically, this can just use the basic { .. } contract, we are not matching the internals and only the fact that the data is an object
        # but works if and only if we use non-lazy type
        let json_dynamic = [
          # TODO: this is interesting and most likely we would want a handling of additional properties to be local in some cases
          # with lazy, this would produce a closed contract. While in k8s case, we want this behavior 99% of the time.
          # with some bad schemas they have, we would basically accept nothing in some cases
          # could also make is_schema func to check if we have a valid name any valid field of a JSON schema
          # even if we skip garbage schemas, a schema defining IntSchema fields should still allow any object.
          # Most likely we will need local evaluation and only here we would always override it with what we get from the local evaluation
          (object_handler schema converted definitions false),
          (array_handler schema converted definitions lazy),
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
            lib.contracts.AnyOf (json_dynamic @ [ref])
          else
            lib.contracts.AnyOf json_dynamic
        in
        schema
        |> match {
          {} => Any,
          # Represent a multi-type schema as an AnyOf Contract
          { ..rest } if std.record.has_field "type" rest && std.typeof rest.type == 'Array =>
            (
              std.array.fold_right
                (fun e acc => acc @ [(json_schema_to_nickel (rest & { type | force = e }) converted definitions false).schema])
                []
                rest.type
              |> lib.contracts.OneOf
            ),
          { ..rest } if std.record.has_field "$ref" rest && !std.record.has_field "properties" rest => ref,
          { type = 'string, enum, ..rest } => string_handler schema,
          { enum, ..rest } => enum_handler enum,
          { const, ..rest } => lib.contracts.Equal const,
          { type = 'string, ..rest } => string_handler schema,
          { type = 'number, ..rest } => int_handler schema,
          { type = 'integer, ..rest } => int_handler schema,
          { type = 'boolean, ..rest } => lib.contracts."Bool",
          { type = 'array, ..rest } => array_handler schema converted definitions lazy,
          { type = 'object, ..rest } => object_handler schema converted definitions lazy,
          { type = 'null, ..rest } => std.contract.from_predicate (fun val => val == null),
          { type, ..rest } if std.typeof type == '"Array" => type |> std.array.map (fun e => { type = "%{e}" }) |> one_of_handler,
          _ => json_dynamic,
        }
      )
      in
      # TOOD: all methods should yield back a 'None or 'Ok contract
      let convertedSchema = (std.array.filter (fun e => e != 'None) [contract, oneOf, anyOf, allOf, not]) in
      let convertedSchema =
        if std.array.length convertedSchema == 1 then
          std.array.first convertedSchema
        else
          std.contract.Sequence convertedSchema
      in
      { schema = convertedSchema, defs = {} },

  # some sorting could resolve issues referncing things in the correct way
  ref_handler
    | { _ | Dyn } -> { _ | JsonSchema } -> String -> Bool -> Dyn
    | default
    = fun converted definitions ref lazy =>
      let ref = std.string.split "/" ref |> std.array.last in
      if std.record.has_field ref converted then
        converted."%{ref}"
      else
        (json_schema_to_nickel definitions."%{ref}" converted definitions lazy).schema,

  k8s_schemas
  # | JsonSchema -> { schema | Dyn, defs | { _ | Dyn } }
  = fun schema =>
    let k8s =
      # TODO: need to also fix some JsonProps stuff for custom resource definitions to work
      # An option is to just premake openAPIV3Schema as JsonSchema and it would work since we are allow extra fields
      # but that would lose the ability to validate the extra fields allowed by k8s
      std.record.update
        "definitions"
        (
          std.record.update
            "io.k8s.apimachinery.pkg.util.intstr.IntOrString"
            {
              oneOf = [
                {
                  type = "number",
                },
                {
                  type = "string",
                },
              ],
            }
            (std.record.get_or "definitions" {} schema)
        )
        schema
    in
    # TODO: A potential option to improve this is to sort the fields and access them based on a specific order.
    # kube schema has a standard convention, Spec is the biggest object for each resource and then List which references the source that references spec.
    # we can utilize some of this info for ourselves and basically build an ordered array so we at least generate the smaller definitions first and then slowly start referncing the bigger one
    # HACK: PodTemplateSpec is the biggest object referenced by many resources, and this allow us to drop a a second before we start accumulating anything
    # TODO: what if we load up PodSpec and from there we
    let hardcoded_optimization = {
      "io.k8s.api.core.v1.PodTemplateSpec" =
        (json_schema_to_nickel k8s.definitions."io.k8s.api.core.v1.PodTemplateSpec" {} k8s.definitions true).schema,

      # Even with this it is slow... It is most likely the recursive nature of the definitions we are generation
      # If this becomes slow and annoying, we can always just pre-creating the full spec as a plain record and we load it manually to avoid its computation
      # or find what is added compared to the original schema and just load that as a definition to be computed and then std.array.Sequence or (&)
      "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps" =
        (json_schema_to_nickel k8s.definitions."io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps" {} k8s.definitions true).schema,
    }
    in
    let k8s =
      k8s.definitions
    in
    # The fold at the top could be dropped here instead
    std.array.fold_right
      (fun e acc =>
        let groupDef = std.array.first e.value.x-kubernetes-group-version-kind in
        let str =
          if groupDef.group == "" then
            "%{groupDef.version}.%{groupDef.kind}"
          else
            "%{groupDef.group}.%{groupDef.version}.%{groupDef.kind}"
        in
        if (
          std.record.has_field "x-kubernetes-group-version-kind" e.value
          && (std.array.length e.value.x-kubernetes-group-version-kind == 1)
          # && !std.string.is_match ".*List" e.field
          # && std.array.elem str filter # TODO: evaluate if this is worth while at runtime on a big set
        ) then
          let schema =
            let required = (std.record.get_or "required" [] e.value) @ ["kind", "apiVersion", ] in
            std.record.update
              "required"
              required
              (
                e.value
                & {
                  properties = {
                    kind = {
                      const = groupDef.kind
                    },
                    apiVersion = {
                      const =
                        if groupDef.group != "" then
                          "%{groupDef.group}/%{groupDef.version}"
                        else
                          "%{groupDef.version}"
                    },
                  },
                }
              )
          in

          let contract = json_schema_to_nickel schema hardcoded_optimization k8s true in
          if groupDef.group == "" then
            acc
            & { "%{groupDef.version}"."%{groupDef.kind}" = contract.schema, }
          else
            acc
            & { "%{groupDef.group}"."%{groupDef.version}"."%{groupDef.kind}" = contract.schema }
        else
          acc
      )
      {}
      (std.record.to_array k8s),

  schema_enforcer
    | String -> String -> String -> JsonSchema -> JsonSchema
    = fun version group crd_kind kube_resource =>
      # Every kube resource need these
      # TODO: extract this to a helper
      let required = ["kind", "apiVersion", "spec"] in
      let patched =
        kube_resource
        & {
          properties = {
            apiVersion = { const = "%{group}/%{version}" },
            kind = { const = crd_kind },
            metadata = { type = "object" }, # TODO: type this like what kube would want
          }
        }
      in
      if std.record.has_field "required" patched then
        std.record.update "required" (patched.required @ required) patched
      else
        std.record.update "required" required patched,

  # This needs the CRD to be able to extract the api info into a valid json schema
  # TODO: the output here should be standarized.
  # While a CRD as a singular reocrd would represent a schema only, it makes more sense to generate a single output format
  crds_schemas
    | Dyn -> Dyn
    = fun crd =>
      std.typeof crd
      |> match {
        'Record =>
          let group = crd.spec.group in
          let kind = crd.spec.names.kind in
          let version = std.array.first crd.spec.versions in
          let schema =
            (
              schema_to_nickel (
                schema_enforcer
                  version.name
                  group
                  kind
                  version.schema.openAPIV3Schema
              )
            ).schema
          in
          {
            "%{group}"."%{kind}"."%{version.name}" = schema
          },
        'Array =>
          (
            crd
            # TODO: this should be handled by the functional contract later on
            |> std.array.filter (fun e => std.typeof e == 'Record && e.kind == "CustomResourceDefinition")
            |> std.array.fold_right
              (fun e acc =>
                let group = e.spec.group in
                let kind = e.spec.names.kind in
                std.array.fold_right
                  (fun e acc =>
                    let contract = schema_to_nickel e.schema.openAPIV3Schema in
                    let version = e.name in
                    let schema = schema_enforcer version group kind e.schema.openAPIV3Schema in
                    acc
                    & {
                      "%{group}"."%{version}"."%{kind}" =
                        (schema_to_nickel schema).schema
                    }
                  )
                  acc
                  e.spec.versions
              )
              {}
          )
      },
}
in
# TODO: this should truly expose only the new exporters
Converters & { Schema = JsonSchema, }
