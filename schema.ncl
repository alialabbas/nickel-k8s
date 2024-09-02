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

      let oneOf =
        # basically oneOf here could have a type or the type could be inferred from the core schema
        # here we force it to normalize the flow
        if std.record.has_field "oneOf" prop then
          let mutated = std.array.map (fun e => e & { type = "number" }) prop.oneOf in
          "," ++ OneOf mutated
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
      if JsonSchemaRangeToNickel range != "" || multiple != "" || oneOf != "" then
        "std.contract.all_of [" ++ baseType ++ JsonSchemaRangeToNickel range ++ multiple ++ oneOf ++ "]"
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
            std.trace "generated definition for %{e.field}" acc ++ "%{SanitizedName e.field} \n = %{SchemaToNickel e.value},\n"
        )
        m%"let rec _definitions =
      {"%
    in result ++ "\n} in\n ",

  ObjectConversion | Schemas.ObjectSchema -> String
    = fun schema =>
      # Get additionalProperties and force it to be true or false only for the use of contracct closure
      let isOpen = std.record.get_or "additionalProperties" DefaultAdditionalProperties schema in
      # Default json schema behavior is to allow additional properties on missing properties
      let isOpen = if std.typeof isOpen == '"Bool" then isOpen else DefaultAdditionalProperties in

      let additionalPropertiesSchema = std.record.get_or "additionalProperties" true schema in
      let additionalPropertiesSchema =
        if std.typeof additionalPropertiesSchema != '"Bool" then
          SchemaToNickel schema.additionalProperties
        else
          std.to_string isOpen
      in

      # TODO: this should be outside with std.contract.all_of
      # here we can know if we are a complex schema, we don't evaluete it, just check it
      # but if we are part of a complex schema we need to be notified about it somehow
      let oneOf = if std.record.has_field "oneOf" schema then OneOf schema.oneOf else "" in
      # let isComplex = schema.isEmptyObject in

      let patternPropertiesSchema =
        (
          schema.patternProperties
          |> std.record.to_array
          |> std.array.fold_right (fun e acc => acc ++ "%{(SanitizedName e.field)} = %{SchemaToNickel e.value},\n") "{ "
        )
        ++ " }"
      in

      let propertiesSchema =
        if schema.properties != {} then
          std.array.fold_right
            (
              fun e acc =>
                let isRequired = std.array.elem e.field schema.required in
                acc ++ "\n" ++ "%{SanitizedName e.field} \n | %{(SchemaToNickel e.value)}" ++ (if isRequired then "," else "| optional,")
            )
            m%"{"%
            (std.record.to_array schema.properties)
          ++ (if isOpen then ".." else "")
          ++ "\n}"
        else
          std.array.fold_right (fun e acc => acc ++ "%{e} | Dyn,\n") "{\n" schema.required ++ "..\n}"
      in

      schema
      |> match {
        # NOTE: required here is the result of the object schema contract
        # First match only a single type of prperties
        {
          properties,
          ..rest
        }
        # TODO: this probably should be here as long as additional properties is bool
        # TODO: remove this oneOf condition later on
        if !std.record.has_field "additionalProperties" schema
          && schema.patternProperties == {} => if oneOf != "" then "std.contract.all_of [\n %{oneOf},\n %{propertiesSchema}\n ]" else std.trace "prop only" propertiesSchema,
        _ => std.trace "modeling json object" "lib.Records.JsonObject %{propertiesSchema}\n %{patternPropertiesSchema} %{additionalPropertiesSchema}"
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
          '"Bool" => SchemaToNickel {}, # TODO: Technically this will yield wrong type when there is only type array and items is false but it doesn't make sense to have an empty array as value from a schema
          '"Record" => SchemaToNickel schema.items,
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
            { ..rest } => "( 'AdditionalItems " ++ (SchemaToNickel schema.items) ++ ")",
          }
        in
        if std.record.has_field "prefixItems" schema then
          std.array.fold_right (fun subSchema acc => acc ++ (SchemaToNickel subSchema) ++ ",") " | Arrays.Tuple [ " schema.prefixItems ++ "] " ++ tupleType
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

  # TODO: This OneOf should be mutual exclusion contract
  OneOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e ++ ",\n") "(lib.OneOf [ " schema ++ "])",
  AnyOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e ++ ",\n") "(std.contract.any_of[ " schema ++ "])",
  AllOf = fun schema => std.array.fold_right (fun e acc => acc ++ SchemaToNickel e ++ ",\n") "(std.contract.all_of[ " schema ++ "])",

  SchemaToNickel = fun schema =>
    let definitions = std.record.get_or "definitions" (std.record.get_or "defs" schema {}) schema in
    let defs =
      if std.record.has_field "definitions" schema then
        GenerateDefinitions schema.definitions
      else
        ""
    in
    defs
    ++ (
      # BUG: {$ref} is impossible to use in pattern matching
      if std.record.has_field "$ref" schema then
        GetRef schema."$ref"
      else
        schema
        |> match {
          {} => "Dyn",
          # These hide object with any of property should be configured
          # probably the way to do this is to check the internals of OneOf type and then find the assioicated property
          { enum, ..rest } => StringConversion schema,
          { const, ..rest } => "std.contract.Equal \"%{const}\"",
          { type = "string", ..rest } => StringConversion schema,
          { type = "number", ..rest } => IntConversion schema,
          { type = "integer", ..rest } => IntConversion schema,
          { type = "boolean", ..rest } => "Bool",
          # { type = "array", ..rest } if !std.record.has_field "items" rest => "(Array Dyn)",
          # { type = "array", ..rest } => "(Array %{SchemaToNickel schema.items})",
          # TODO: arrays can be a bit special because of who knows the idiot that thought it is a good idea to allow about anything in this forsaken world
          # Gitlab ci for example throws oneOf then properties in separate sections to define the schema even when they could just defined it inside the object itself.
          # option 1: refuse stupid schemas because I give up on idiocy
          # option 2: mutation internally.... Could mutate the data internally to merge back the object and handle it gracely
          # option 3: handle this because there might be more weird cases like this
          { type = "array", ..rest } => ArrayConversion schema,

          # TODO: Consider moving object handling logic all in the method itself rather than here
          # All these object handling could be optimized and pulled into ObjectConversion
          # That would simplify this method signifcantly
          # Object Handling
          { type = "object" } => "{ .. }",
          { type = "object", description | String } => "{ .. }",
          # TODO: this additional stuff will need special magic
          # TODO: This most likely more appropriate in the object conversion TBD
          # What is this pattern that is not captured for kube here
          # { type = "object", additionalProperties | std.contract.any_of [{ .. }, String ], ..rest } if !std.record.has_field "properties" rest => "{ _ | Dyn }",
          { type = "object", ..rest } => std.trace "Handling Object" ObjectConversion schema,
          { type = "null", ..rest } => "null", # BUG: treesitter no handling this
          # TODO: all of these should really be appended to the contract as the first thing to evaluate potentially
          # and most likely we need a simple optimization to check if we have multiple schema validation, we dectitate this by checking if we have complex schema
          { oneOf, ..rest } => OneOf schema.oneOf,
          { allOf, ..rest } => AllOf schema.allOf,
          { anyOf, ..rest } => AnyOf schema.anyOf,
          { not, ..rest } => "std.contract.not %{SchemaToNickel schema.not}",
          # Array of Types is the same as oneOf
          { type, ..rest } if std.typeof type == '"Array" => type |> std.array.map (fun e => { type = "%{e}" }) |> OneOf,
          # Why are we getting here, why is it not matching the object with rest
          _ => std.trace "unmatched pattern, defaulting to object" ObjectConversion schema,
        }
    ),
}
in
Converters
