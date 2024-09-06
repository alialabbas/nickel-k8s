# TODO: add back description generation with an option flag, have to escape some magic already mind as well include the description
# TODO: need to start including the lib because complex schemas will not be convertable otherwise
# TODO: can't use contract changing "|" inside of anyOf and allOf and so on, probably better to wrap everything with all_of
# TODO: handling complex arrays with items and properties and one of and any of and so on
# TOOD: regex is not the issue, the issue the escape of the regex to this language that needs to be handled correctly
# TODO: Look ahead and back regex. Would never work if we keep those all the time.
# TODO: format: are those really standard or just a bunch of magic people create and use their own
# TODO: most likely need a wrapper around basic contracts, i.e. Number only or something simple that is not wrapped inside OneOf relations
# TODO: do we really need to declare json enums with nickel tag/enum. We are checking for value in something which is simple to do. It is more an optimization to allow the lang to do its own thing rather than relying on dictionaries
# TODO: double check pattern matcher implemention and make sure it works correctly
# TODO: check additional properties modifier and see if it makes sense to have it modified by the caller and not the system
# TODO: general print cleanup to only do compelx expression when we really have to
# BUG: ContractA | ContractB should this fail if the additional value in A is not defined in B
# This bug means we will always need to check the subschema first then the super
# TODO: big schema contract to avoid mistyping and faulty schemas in tests
let Nullable | doc m%"Apply the Contract to an array and allow it to also be assigned as null"%
  = fun contract =>
    fun label value =>
      if value == null then
        null
      else
        std.contract.apply (contract) label value
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
    isEmptyObject | Bool = properties == {} && patternProperties == {} && std.typeof additionalProperties == 'Bool,
    ..
  },
}
in

let Converters = {

  IntConversion | Schemas.NumberSchema -> String
    = fun prop =>
      let multiple =
        if std.record.has_field "multipleOf" prop then
          ", lib.Numbers.MultipleOf %{std.string.from_number prop.multipleOf}"
        else
          ""
      in

      # let oneOf =
      #   # basically oneOf here could have a type or the type could be inferred from the core schema
      #   # here we force it to normalize the flow
      #   if std.record.has_field "oneOf" prop then
      #     let mutated = std.array.map (fun e => e & { type = "number" }) prop.oneOf in
      #     "," ++ OneOf mutated
      #   else
      #     ""
      # in

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
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } if maximum == null => ", lib.Numbers.MinRange %{std.string.from_number minimum} %{std.string.from_bool (!exclusiveMinimum)}",
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } if minimum == null => ", lib.Numbers.MaxRange %{std.string.from_number maximum} %{std.string.from_bool (!exclusiveMaximum)}",
          { minimum, maximum, exclusiveMaximum, exclusiveMinimum } => ", lib.Numbers.InRange %{std.string.from_number minimum} %{std.string.from_bool (!exclusiveMinimum)} %{std.string.from_number maximum} %{std.string.from_bool (!exclusiveMaximum)}",
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

  StringConversion | Schemas.StringSchema -> String
    = fun prop =>
      let minLen =
        if std.record.has_field "minLength" prop then
          ", lib.Strings.MinLength %{std.string.from_number prop.minLength}"
        else
          ""
      in
      let maxLen =
        if std.record.has_field "maxLength" prop then
          ", lib.Strings.MaxLength %{std.string.from_number prop.maxLength}"
        else
          ""
      in
      let pattern =
        if std.record.has_field "pattern" prop then
          m%", lib.Strings.Regex "%{prop.pattern}""% # TODO: RAW STRINGS
        else
          ""
      in
      let type =
        # HACK: formatter has a bug, this doesn't affect the generation and just stops us from formatting the generated file
        if std.record.has_field "enum" prop && std.array.length prop.enum == 1 then
          # TODO: need a way to escape these, quotes will work but need special tokens to replace them
          # Bug: can't assign an enum to an exporter property as this contract will fail miserably
          "lib.Enum.StringOrEnum [| '\"%{std.array.first prop.enum}\" |]"
        else if std.record.has_field "enum" prop then
          std.array.fold_right
            (
              # We need to check the empty array here and escape the quotes to get '"" as a tag
              fun e acc => acc ++ " '\"%{e}\", "
            )
            "lib.Enum.StringOrEnum [| "
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
      # TODO: RAW STRINGS
      std.trace "escaping field %{field}" m%""%{field}""%,

  # Gets the internal definitions in a schema and population a nickel type string for each
  GenerateDefinitions = fun defs =>
    let result =
      defs
      |> std.record.to_array
      |> std.array.fold_right
        (
          fun e acc =>
            std.trace "generated definition for %{e.field}" acc ++ "%{SanitizedName e.field} \n = %{SchemaToNickel e.value false},\n"
        )
        m%"let rec _definitions =
      {"%
    in result ++ "\n} in\n ",

  ObjectConversion
    | doc m%"
        Generate a contract equivalent of a json schema. noLazy is a context to force the contract to be a non-lazy record evaluation
        This flag is necessary when we evaluate schemas inside of a oneOf subschema
      "%
    # : Dyn -> Bool -> String
    | Schemas.ObjectSchema -> Bool -> String
    = fun schema noLazy =>
      # Get additionalProperties and force it to be true or false only for the use of contracct closure
      let isOpen = std.record.get_or "additionalProperties" DefaultAdditionalProperties schema in
      # Default json schema behavior is to allow additional properties on missing properties
      let isOpen = if std.typeof isOpen == '"Bool" then isOpen else DefaultAdditionalProperties in

      let additionalPropertiesSchema = std.record.get_or "additionalProperties" true schema in
      let additionalPropertiesSchema =
        if std.typeof additionalPropertiesSchema != '"Bool" then
          SchemaToNickel schema.additionalProperties noLazy
        else
          std.to_string isOpen
      in

      # TODO: this should be outside with std.contract.all_of
      # let noLazy =
      #   !(
      #     std.record.has_field "oneOf" schema
      #     || std.record.has_field "allOf"
      #     || std.record.has_field
      #     || "anyOf"
      #   )
      #   && noLazy
      # in
      # let oneOf = if std.record.has_field "oneOf" schema then OneOf schema.oneOf else "" in
      # let isComplex = schema.isEmptyObject in
      let patternPropertiesSchema =
        (
          schema.patternProperties
          |> std.record.to_array
          |> std.array.fold_right (fun e acc => acc ++ "%{(SanitizedName e.field)} = %{SchemaToNickel e.value noLazy},\n") "{ "
        )
        ++ " }"
      in

      let propertiesSchema =
        if schema.properties != {} then
          std.array.fold_right
            (
              fun e acc =>
                let isRequired = std.array.elem e.field schema.required in
                acc ++ "\n" ++ "%{SanitizedName e.field} \n | %{(SchemaToNickel e.value noLazy)}" ++ (if isRequired then "," else "| optional,")
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
            (
              fun e acc =>
                let isRequired = std.array.elem e.field schema.required in
                acc ++ "\n" ++ "%{SanitizedName e.field} \n = { contract = %{(SchemaToNickel e.value noLazy)}" ++ ", \n optional = %{std.to_string isRequired} },"
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
        if !std.record.has_field "additionalProperties" schema
          && schema.patternProperties == {}
          && !noLazy => std.trace "prop only" propertiesSchema,
        _ => std.trace "modeling json object" "lib.Records.JsonObject %{nonLazyProperties}\n %{patternPropertiesSchema} %{additionalPropertiesSchema}"
      },

  ArrayConversion | Schemas.ArraySchema -> String
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
          '"Bool" => SchemaToNickel {} false, # TODO: Technically this will yield wrong type when there is only type array and items is false but it doesn't make sense to have an empty array as value from a schema
          '"Record" => SchemaToNickel schema.items false,
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
          { min, } => "| lib.Arrays.Length { min = %{std.to_string min} } ",
          { max, } => "| lib.Arrays.Length { max = %{std.to_string max} }",
          { min, max } => "| lib.Arrays.Length { min = %{std.to_string min},  max = %{std.to_string max} }",
          {} => "", # TODO: Is this safe to assume
        }
      in
      let setContract =
        let hasSetFlag = std.record.get_or "uniqueness" false schema in
        if hasSetFlag then
          "| lib.Arrays.AsSet"
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
            { ..rest } => "( 'AdditionalItems " ++ (SchemaToNickel schema.items false) ++ ")",
          }
        in
        if std.record.has_field "prefixItems" schema then
          std.array.fold_right (fun subSchema acc => acc ++ (SchemaToNickel subSchema false) ++ ",") " | Arrays.Tuple [ " schema.prefixItems ++ "] " ++ tupleType
        else
          ""
      in
      "(Array %{arrayType}" ++ ")" ++ arrayLength ++ tupleContract ++ setContract,
  # tupleContract

  DefaultAdditionalProperties
    | doc "simple flag to control the default schema bevaior, useful when generating many defintions and want to explicitly not allow the bad schema to accept more than it should like the k8 definitions"
    | Bool
    | default
    = true,

  # NOTE: contract defaulted method to allow customization by external user if they want to handle it differently, this now is done only for k8s
  # TODO: Expirement with a toggle to control the prefix for generation. This could be useful

  OneOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e true ++ ",\n") "(lib.OneOf [ " schema ++ "])",
  AnyOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e true ++ ",\n") "(std.contract.any_of[ " schema ++ "])",
  AllOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e true ++ ",\n") "(std.contract.all_of[ " schema ++ "])",
  Enum = fun schema => std.array.fold_right (fun e acc => acc ++ (PrintConstValue e) ++ ",\n") "lib.Enum.ArrayEnum [ " schema ++ "]",

  PrintConstValue = fun schema =>
    let recordAsString =
      (
        std.record.to_array schema
        |> std.array.fold_right
          (
            fun e acc => acc ++ e.field ++ "=" ++ (PrintConstValue e.value) ++ ",\n"
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

  # basically the options are;
  # 1. we unpack the boolean predicate here first before we generate the contract
  # 2. this means an extra matther before and after and we need, is there precedence order for these
  # 3. rather than adding the pipe ourselves without knowing what schemas to generate, we should create an array that we append
  # is the current schema always possible to pipe its properties with multiple contracts
  SchemaToNickel = fun schema lazy =>
    let definitions = std.record.get_or "definitions" (std.record.get_or "defs" schema {}) schema in
    let oneOf = if std.record.has_field "oneOf" schema && std.record.has_field "type" schema then (OneOf schema.oneOf) else "" in
    let allOf = if std.record.has_field "allOf" schema && std.record.has_field "type" schema then (AllOf schema.allOf) else "" in
    let anyOf = if std.record.has_field "anyOf" schema && std.record.has_field "type" schema then (AnyOf schema.anyOf) else "" in
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
        GetRef schema."$ref"
      else
        schema
        |> match {
          {} => "Dyn",
          { type = "string", enum, ..rest } => StringConversion schema,
          { enum, ..rest } => Enum enum,
          { const, ..rest } => "std.contract.from_predicate(fun val => val == %{PrintConstValue const})",
          { type = "string", ..rest } => StringConversion schema,
          { type = "number", ..rest } => IntConversion schema,
          { type = "integer", ..rest } => IntConversion schema,
          { type = "boolean", ..rest } => "Bool",
          { type = "array", ..rest } => ArrayConversion schema,
          { type = "object" } => "{ .. }",
          { type = "object", description | String } => "{ .. }",
          { type = "object", ..rest } => std.trace "Handling Object" ObjectConversion schema lazy,
          { type = "null", ..rest } => "std.contract.from_predicate(fun val => val == null)", # BUG: treesitter no handling this
          # TODO: need a way to only generate anyOf and such if and only if we had a complex schema
          { oneOf, ..rest } => OneOf schema.oneOf,
          { allOf, ..rest } => AllOf schema.allOf,
          { anyOf, ..rest } => AnyOf schema.anyOf,
          { not, ..rest } => "(std.contract.not %{SchemaToNickel schema.not false})",
          { type, ..rest } if std.typeof type == '"Array" => type |> std.array.map (fun e => { type = "%{e}" }) |> OneOf,
          _ => std.trace "unmatched pattern, defaulting to object" ObjectConversion schema lazy,
        }
    )
    in
    let defs =
      if std.record.has_field "definitions" schema then
        GenerateDefinitions schema.definitions
      else
        ""
    in
    let convertedSchema = (std.array.filter (fun e => e != "") [schemaStr, oneOf, anyOf, allOf]) in
    defs
    # BUG: std.contract.any_of | std.contract.not on basic types yields incorrect result
    # TODO: optimize this to not print out paranthesis on a single expression
    # TODO/BUG: what happens when we do the following { basic record } | myContract, this fails in complex jsonObject with optionality
    # basically somehow aggregating the contract seems to fail
    ++ (
      if std.array.length convertedSchema > 1 then
        "(std.contract.all_of ["
        ++ (std.string.join ",\n" convertedSchema)
        ++ "])"
      else
        schemaStr
    ),

  GetRef
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
