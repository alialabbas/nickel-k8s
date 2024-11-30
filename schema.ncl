let lib = import "lib.ncl" in
let Nullable | doc m%"Apply the Contract to an array and allow it to also be assigned as null"%
  = fun contract =>
    fun label value =>
      if value == null then
        null
      else
        std.contract.apply (contract) label value
  in

let escape_string = fun str => std.string.replace "\"" "'" str |> std.string.replace "\\" "\\\\" in

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
        _ =>
          'Error {
            message = "Expected either an array or string, got %{std.to_string (std.typeof value)}"
          }
      }
    )
  in
  {
    type
      | SchemaType
      | optional,
    markdownDescription | String | default = "",
    description | String | default = "",

    # Integer/Number Props
    minimum | Nullable Number | optional,
    maximum | Nullable Number | optional,
    exclusiveMaximum | std.contract.any_of [ Number, Bool ] | optional,
    exclusiveMinimum | std.contract.any_of [ Number, Bool ] | optional,
    multipleOf | Number | optional,

    # Array Props
    items | std.contract.any_of [ Bool, { .. }] | optional, # TODO: make a schema contract
    prefixItems | Array { .. } | optional, # Schema contract please
    contains | { .. } | optional,
    minContains | std.number.PosNat | optional,
    maxContains | std.number.PosNat | optional,
    minItems | std.number.Nat | optional,
    maxItems | std.number.PosNat | optional,
    uniqueness | Bool | optional,

    # String Props
    minLength | std.number.Integer | optional,
    maxLength | std.number.Integer | optional,
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

    # Object Props
    required | Array String | default = [],
    properties | { _ | { .. } } | default = {},
    patternProperties | { _ | { .. } } | default = {},
    # TODO: this need special contract, bool or schema
    additionalProperties | Dyn | optional,

    oneOf | Array JsonSchema | optional,
    anyOf | Array JsonSchema | optional,
    allOf | Array JsonSchema | optional,
    not | JsonSchema | optional,
    ..
  }
in
let Schemas = {
  NumberSchema = {
    type | std.enum.TagOrString | [| 'number, 'integer |],
    minimum | Nullable Number | optional,
    maximum | Nullable Number | optional,
    exclusiveMaximum | std.contract.any_of [ Number, Bool ] | optional,
    exclusiveMinimum | std.contract.any_of [ Number, Bool ] | optional,
    multipleOf | Number | optional,
    markdownDescription | String | default = "",
    description | String | default = "",
    .. # We are always allowing more than usual since we want to allow custom definitions like kube to work
  },

  ArraySchema = {
    type | String | force = "array",
    items | std.contract.any_of [ Bool, { .. }] | optional, # TODO: make a schema contract
    prefixItems | Array { .. } | optional, # Schema contract please
    contains | { .. } | optional,
    minContains | std.number.PosNat | optional,
    maxContains | std.number.PosNat | optional,
    minItems | std.number.Nat | optional,
    maxItems | std.number.PosNat | optional,
    uniqueness | Bool | optional,
    ..
  },

  StringSchema = {
    type = "string",
    minLength | std.number.Integer | optional,
    maxLength | std.number.Integer | optional,
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
    description | String | optional,
    ..
  },

  # TODO: is it possible to type instead of contract check, benefit of a contract is playing with the fields without changing the underlying type
  ObjectSchema = {
    required | Array String | default = [],
    type = "object",
    description | String | default = "",
    # TODO: Technically what is inside is a schema, if we can capture that, that would make the code better
    properties | { _ | { .. } } | default = {},
    patternProperties | { _ | { .. } } | default = {},
    # TODO: this need special contract, bool or schema
    additionalProperties | Dyn | optional,
    ..
  },
}
in

let Converters = {

  int_handler | Schemas.NumberSchema -> String
    = fun prop =>
      let multiple =
        if std.record.has_field "multipleOf" prop then
          ", lib.numbers.MultipleOf %{std.string.from_number prop.multipleOf}"
        else
          ""
      in

      # NOTE: ranged is dynamically generated, it looks like NumberSchema but IT IS NOT
      # Draf4 and Draft7 of JsonScheam allow exlusiveX to be bool and the latter allows it to set the value.
      # Here we always want the value to come only mimumum and exlucisveX is just a bool decided the range to use
      # TODO: exlclusive handling here is wrong, this is generating false all the time
      let range = {
        exclusiveMinimum = std.record.has_field_with_opts "exclusiveMinimum" prop,
        exclusiveMaximum = std.record.has_field_with_opts "exclusiveMaximum" prop,
        minimum =
          std.record.get_or
            "minimum"
            (if (std.record.get_or "exclusiveMinimum" null prop |> std.typeof) == '"Number" then prop.exclusiveMinimum else null)
            prop,
        maximum =
          std.record.get_or
            "maximum"
            (if (std.record.get_or "exclusiveMaximum" null prop |> std.typeof) == '"Number" then prop.exclusiveMaximum else null)
            prop,
      }
      in
      # TODO: this most likely doesn't need to be a function and just use the value directly
      let JsonSchemaRangeToNickel = fun range =>
        range
        |> match {
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } if maximum == null && minimum == null => "",
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } if maximum == null => ", lib.numbers.MinRange %{std.string.from_number minimum} %{std.string.from_bool (!exclusiveMinimum)}",
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } if minimum == null => ", lib.numbers.MaxRange %{std.string.from_number maximum} %{std.string.from_bool (!exclusiveMaximum)}",
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } => ", lib.numbers.InRange %{std.string.from_number minimum} %{std.string.from_bool (!exclusiveMinimum)} %{std.string.from_number maximum} %{std.string.from_bool (!exclusiveMaximum)}",
        }
      in
      let baseType =
        prop.type
        |> match {
          'integer => "std.number.Integer",
          'number => "Number",
        }
      in
      if JsonSchemaRangeToNickel range != "" || multiple != "" then
        "std.contract.all_of [" ++ baseType ++ JsonSchemaRangeToNickel range ++ multiple ++ "]"
      else
        baseType,

  stirng_handler | Schemas.StringSchema -> String
    = fun prop =>
      let minLen =
        if std.record.has_field "minLength" prop then
          ", lib.strings.MinLength %{std.string.from_number prop.minLength}"
        else
          ""
      in
      let maxLen =
        if std.record.has_field "maxLength" prop then
          ", lib.strings.MaxLength %{std.string.from_number prop.maxLength}"
        else
          ""
      in
      let pattern =
        let escapeString = fun str => std.array.fold_right (fun e acc => if e == "\\" then e ++ "\\" ++ acc else e ++ acc) "" (std.string.characters str) in
        if std.record.has_field "pattern" prop then
          m%", lib.strings.Regex "%{escapeString prop.pattern}""% # TODO: RAW STRINGS
        else
          ""
      in
      let type =
        # HACK: formatter has a bug, this doesn't affect the generation and just stops us from formatting the generated file
        if std.record.has_field "enum" prop && std.array.length prop.enum == 1 then
          # TODO: need a way to escape these, quotes will work but need special tokens to replace them
          # Bug: can't assign an enum to an exporter property as this contract will fail miserably
          "lib.enum.StringOrEnum [| '\"%{std.array.first prop.enum}\" |]"
        else if std.record.has_field "enum" prop then
          std.array.fold_right
            (
            # We need to check the empty array here and escape the quotes to get '"" as a tag
            fun e acc => acc ++ " '\"%{e}\", "
            )
            "lib.enum.StringOrEnum [| "
            prop.enum
          ++ " |]"
        else if std.record.has_field "format" prop then
          prop.format
          |> match {
            "uuid" => " | UUID",
            "date-time" => " | DateTime",
            "date" => "| Date",
            "time" => "| Time",
            # TODO: implement the rest here
            _ => "String",
          }
        else
          "String"
      in
      # NOTE: for dealing with mixing array and large change of contracts inside of array
      if minLen != "" || maxLen != "" || pattern != "" then
        "std.contract.all_of [ " ++ type ++ minLen ++ maxLen ++ pattern ++ "]"
      else
        type,

  SanitizedName = fun field =>
    let keywords = ["if", "else if", "else", "let", "in", "match"] in
    if !std.array.elem field keywords && std.string.is_match "^[a-zA-Z][a-zA-Z0-9-_]+$" field then
      field
    else
      m%""%{field}""%,

  # Gets the internal definitions in a schema and population a nickel type string for each
  definitions_handler = fun defs =>
    let result =
      defs
      |> std.record.to_array
      |> std.array.fold_right
        (fun e acc =>
          acc ++ "%{SanitizedName e.field} \n = %{json_schema_to_nickel e.value false},\n"
        )
        m%"let rec _definitions =
      {"%
    in result ++ "\n} in\n ",

  object_handler
    | doc m%"
        Generate a contract equivalent of a json schema. noLazy is a context to force the contract to be a non-lazy record evaluation
        This flag is necessary when we evaluate schemas inside of a oneOf subschema
      "%
    | Schemas.ObjectSchema -> Bool -> String
    = fun schema noLazy =>
      # Get additionalProperties and force it to be true or false only for the use of contracct closure
      let isOpen = std.record.get_or "additionalProperties" options.default_additional_properties schema in
      # Default json schema behavior is to allow additional properties on missing properties
      let isOpen = if std.typeof isOpen == '"Bool" then isOpen else options.default_additional_properties in

      let additionalPropertiesSchema = std.record.get_or "additionalProperties" true schema in
      let additionalPropertiesSchema =
        if std.typeof additionalPropertiesSchema != '"Bool" then
          json_schema_to_nickel schema.additionalProperties noLazy
        else
          std.to_string isOpen
      in

      let patternPropertiesSchema =
        (
          schema.patternProperties
          |> std.record.to_array
          |> std.array.fold_right (fun e acc => acc ++ "%{(SanitizedName e.field)} = %{json_schema_to_nickel e.value noLazy},\n") "{ "
        )
        ++ " }"
      in

      let propertiesSchema =
        if schema.properties != {} then
          std.array.fold_right
            (fun e acc =>
              let isRequired = std.array.elem e.field schema.required in
              acc ++ "\n" ++ "%{SanitizedName e.field} \n %{doc_handler e.value} | %{(json_schema_to_nickel e.value noLazy)}" ++ (if isRequired then "," else "| optional,")
            )
            m%"{"%
            (std.record.to_array schema.properties)
          ++ (if isOpen then ".." else "")
          ++ "\n}"
        else
          std.array.fold_right (fun e acc => acc ++ "%{e} | Dyn,\n") "{\n" schema.required ++ "..\n}"
      in

      let nonLazyProperties =
        if schema.properties != {} then
          std.array.fold_right
            (fun e acc =>
              let isRequired = if schema.required == [] then true else std.array.elem e.field schema.required in
              acc ++ "\n" ++ "%{SanitizedName e.field} \n = { contract = %{(json_schema_to_nickel e.value noLazy)}" ++ ", \n optional = %{std.to_string isRequired} },"
            )
            m%"{"%
            (std.record.to_array schema.properties)
          ++ "\n}"
        else
          std.array.fold_right (fun e acc => acc ++ "%{e} = { contract = Dyn, optional = false,} ,\n") "{\n" schema.required ++ "\n}"
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
          && schema.required == [] => "{ _ | %{additionalPropertiesSchema}}",
        {
          properties,
          ..rest
        }
        # TODO: this probably should be here as long as additional properties is bool
        # TODO: remove this oneOf condition later on
        if (!std.record.has_field "additionalProperties" schema || (std.record.has_field "additionalProperties" schema && std.typeof schema.additionalProperties == 'Bool))
          && schema.patternProperties == {}
          && !noLazy => propertiesSchema,
        _ => "(lib.records.JsonObject %{nonLazyProperties}\n %{patternPropertiesSchema} %{additionalPropertiesSchema})"
      },

  array_handler | Schemas.ArraySchema -> String
    = fun schema =>
      # What is the best way to make sure we don't want a type.
      # items false means nothing when it is by itself so not gonna bother with that corner case
      # we want to capture the initial schema if this value is not a bool
      # This should always be the first type to process
      # Maybe using std.contract.all_of here would be appropriate to apply these contracts in isolation?
      let arrayType =
        # TODO: This should check if items exist
        let items = std.typeof (std.record.get_or "items" false schema) in
        items
        |> match {
          '"Bool" => json_schema_to_nickel {} false, # TODO: Technically this will yield wrong type when there is only type array and items is false but it doesn't make sense to have an empty array as value from a schema
          '"Record" => json_schema_to_nickel schema.items false,
        }
      in
      let arrayLength =
        let range =
          {
            min = std.record.get_or "minItems" null schema,
            max = std.record.get_or "maxItems" null schema
          }
          |> std.record.filter (fun k v => v != null)
        in
        range
        |> match {
          { min, } => "| lib.arrays.Length { min = %{std.to_string min} } ",
          { max, } => "| lib.arrays.Length { max = %{std.to_string max} }",
          { min, max } => "| lib.arrays.Length { min = %{std.to_string min},  max = %{std.to_string max} }",
          {} => "", # TODO: Is this safe to assume
        }
      in
      let setContract =
        let hasSetFlag = std.record.get_or "uniqueness" false schema in
        if hasSetFlag then
          "| lib.arrays.AsSet"
        else
          ""
      in
      # TODO: tuple type won't work without special handling
      let tupleContract =
        let tupleType =
          std.record.get_or "items" true schema
          |> match {
            false => "'Exact",
            true => "('AdditionalItems Dyn)",
            { ..rest } => "( 'AdditionalItems " ++ (json_schema_to_nickel schema.items false) ++ ")",
          }
        in
        if std.record.has_field "prefixItems" schema then
          std.array.fold_right (fun subSchema acc => acc ++ (json_schema_to_nickel subSchema false) ++ ",") " | Arrays.Tuple [ " schema.prefixItems ++ "] " ++ tupleType
        else
          ""
      in
      "(Array %{arrayType}" ++ ")" ++ arrayLength ++ tupleContract ++ setContract,
  # tupleContract

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
        = true,
    },

  # NOTE: contract defaulted method to allow customization by external user if they want to handle it differently, this now is done only for k8s
  # TODO: Expirement with a toggle to control the prefix for generation. This could be useful

  one_of_handler = fun schema => std.array.fold_right (fun e acc => acc ++ json_schema_to_nickel e true ++ ",\n") "(lib.contracts.OneOf [ " schema ++ "])",
  any_of_handler = fun schema => std.array.fold_right (fun e acc => acc ++ json_schema_to_nickel e true ++ ",\n") "(std.contract.any_of[ " schema ++ "])",
  all_of_handler = fun schema => std.array.fold_right (fun e acc => acc ++ json_schema_to_nickel e true ++ ",\n") "(std.contract.all_of[ " schema ++ "])",
  enum_handler = fun schema => std.array.fold_right (fun e acc => acc ++ (print_const_value e) ++ ",\n") "lib.enum.ArrayEnum [ " schema ++ "]",

  print_const_value = fun schema =>
    let recordAsString =
      (
        std.record.to_array schema
        |> std.array.fold_right
          (fun e acc => acc ++ e.field ++ "=" ++ (print_const_value e.value) ++ ",\n"
          )
          "{"
      )
      ++ "}"
    in
    std.typeof schema
    |> match {
      'String => "\"%{schema}\"",
      'Bool or 'Number => std.to_string schema,
      'Record => recordAsString,
    },

  doc_handler
    | Dyn -> String
    | default
    = fun obj =>
      if options.include_docs && std.record.has_field "description" obj then
        m%"| doc "%{escape_string obj.description}""%
      else
        "",

  json_schema_to_nickel
    | doc m%"
      Convert a json schema to a nickel string that can be exported using `nickel export -f raw`.
      `lazy` controls the type of contracts generated for Records. By design those are lazy and in some cases like in allOf and OneOf expressions
      reocrds need to be non-lazy to be able to check if the a schema predicate is satisfied or not.
      Passing a false will force all records to be non-lazy including simple ones that could be represented as a simple nickel record contract.
    "%
    | JsonSchema -> Bool -> String
    = fun schema lazy =>
      let definitions = std.record.get_or "definitions" (std.record.get_or "defs" schema {}) schema in
      let oneOf = if std.record.has_field "oneOf" schema && std.record.has_field "type" schema then (one_of_handler schema.oneOf) else "" in
      let allOf = if std.record.has_field "allOf" schema && std.record.has_field "type" schema then (all_of_handler schema.allOf) else "" in
      let anyOf = if std.record.has_field "anyOf" schema && std.record.has_field "type" schema then (any_of_handler schema.anyOf) else "" in
      let isComplex =
        lazy
        || std.record.has_field "oneOf" schema
        # || std.record.has_field "not" schema
        || std.record.has_field "anyOf" schema
        || std.record.has_field "allOf" schema
      in
      let schemaStr = (
        # BUG: {$ref} is impossible to use in pattern matching
        if std.record.has_field "$ref" schema then
          ref_handler schema."$ref"
        else
          schema
          |> match {
            # Represent a multi-type schema as an AnyOf Contract
            { ..rest } if std.record.has_field "type" rest && std.typeof rest.type == 'Array =>
              (
                std.array.fold_right
                  (fun e acc => acc ++ (json_schema_to_nickel (rest & { type | force = e }) false) ++ ",\n")
                  "lib.contracts.OneOf [ "
                  rest.type
              )
              ++ "]",
            { type = 'string, enum, ..rest } => stirng_handler schema,
            { enum, ..rest } => enum_handler enum,
            { const, ..rest } => "std.contract.from_predicate(fun val => val == %{print_const_value const})",
            { type = 'string, ..rest } => stirng_handler schema,
            { type = 'number, ..rest } => int_handler schema,
            { type = 'integer, ..rest } => int_handler schema,
            { type = 'boolean, ..rest } => "Bool",
            { type = 'array, ..rest } => array_handler schema,
            { type = 'object, ..rest } => object_handler schema lazy,
            { type = 'null, ..rest } => "std.contract.from_predicate(fun val => val == null)", # BUG: treesitter no handling this
            # TODO: need a way to only generate anyOf and such if and only if we had a complex schema
            { oneOf, ..rest } => one_of_handler schema.oneOf,
            { allOf, ..rest } => all_of_handler schema.allOf,
            { anyOf, ..rest } => any_of_handler schema.anyOf,
            { not, ..rest } => "(std.contract.not %{json_schema_to_nickel schema.not false})",
            { type, ..rest } if std.typeof type == '"Array" => type |> std.array.map (fun e => { type = "%{e}" }) |> one_of_handler,
            # TODO: What is the exact expecation when a type is missing
            # where we assume the user just want an object but technically it could be a mix of int schema + obj schema
            # Should those be evaluated based on those type and it is the type is a union of all or what
            { ..rest } if !std.record.has_field "type" rest && std.record.length rest == 0 => "Dyn",
            _ => object_handler schema lazy,
          }
      )
      in
      let defs =
        if std.record.has_field "definitions" schema then
          definitions_handler schema.definitions
        else
          ""
      in
      let convertedSchema = (std.array.filter (fun e => e != "") [schemaStr, oneOf, anyOf, allOf]) in
      defs
      ++ (
        if std.array.length convertedSchema > 1 then
          "(std.contract.all_of ["
          ++ (std.string.join ",\n" convertedSchema)
          ++ "])"
        else
          schemaStr
      ),

  ref_handler
    | (String -> String)
    | default
    = fun ref =>
      let ref = std.string.split "/" ref in
      ref
      |> match {
        ["#", "definitions", ..rest] => "_definitions.%{SanitizedName (std.array.first rest)}",
        ["#", "defs", ..rest] => "_definitions." ++ std.array.first rest
      },
}
in
Converters
