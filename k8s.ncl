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
    isEmptyObject | Bool = properties == {} && patternProperties == {} && std.typeof additionalProperties == 'Bool,
    ..
  },
}
in

let Converters = {
  IntConversion
    | Schemas.NumberSchema -> String
    | default
    = fun prop => "",

  StringConversion | Schemas.StringSchema -> String
    = fun prop => "",

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
    | Schemas.ObjectSchema -> Bool -> String
    = fun schema noLazy =>
      let propertiesSchema =
        if schema.properties != {} then
          std.array.fold_right
            (
              fun e acc =>
                let isRequired = std.array.elem e.field schema.required in
                let nickelContract = SchemaToNickel e.value noLazy in
                # we only care about non-empty array contracts from this deep merge
                if nickelContract != "" then
                  acc
                  ++ "\n"
                  ++ "%{SanitizedName e.field} \n | %{(nickelContract)}"
                  ++ (if isRequired then "," else "| optional,")
                else
                  acc
            )
            m%""%
            (std.record.to_array schema.properties)
        else
          ""
      in
      if propertiesSchema != "" then
        "{\n" ++ propertiesSchema ++ "..\n}"
      else
        "",

  ArrayConversion
    | Schemas.ArraySchema -> String
    | default
    = fun schema =>
      let arrayType =
        # TODO: This should check if items exist
        let items = std.typeof (std.record.get_or "items" false schema) in
        items
        |> match {
          '"Bool" => SchemaToNickel {} false, # TODO: Technically this will yield wrong type when there is only type array and items is false but it doesn't make sense to have an empty array as value from a schema
          '"Record" => SchemaToNickel schema.items false,
        }
      in
      let mergeKey = std.record.get_or "x-kubernetes-patch-merge-key" "" schema in
      if mergeKey != "" && arrayType != "" then
        m%"(Array %{arrayType}) | lib.FromListToMap "%{mergeKey}""%
      else if mergeKey != "" then
        m%"lib.FromListToMap "%{mergeKey}""%
      else
        arrayType,

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

  SchemaToNickel = fun schema lazy =>
    let schemaStr = (
      # BUG: {$ref} is impossible to use in pattern matching
      if std.record.has_field "$ref" schema then
        GetRef schema."$ref"
      else
        schema
        |> match {
          {} => "",
          { type = "string", enum, ..rest } => "",
          { enum, ..rest } => "",
          { const, ..rest } => "",
          { type = "string", ..rest } => "",
          { type = "number", ..rest } => "",
          { type = "integer", ..rest } => "",
          { type = "boolean", ..rest } => "",
          { type = "array", ..rest } => ArrayConversion schema,
          # { type = "object" } => "{ .. }",
          # { type = "object", description | String } => "{ .. }",
          { type = "object", ..rest } => std.trace "Handling Object" ObjectConversion schema lazy,
          # { type = "null", ..rest } => "std.contract.from_predicate(fun val => val == null)", # BUG: treesitter no handling this
          # TODO: need a way to only generate anyOf and such if and only if we had a complex schema
          # { oneOf, ..rest } => OneOf schema.oneOf,
          # { allOf, ..rest } => AllOf schema.allOf,
          # { anyOf, ..rest } => AnyOf schema.anyOf,
          # { not, ..rest } => "(std.contract.not %{SchemaToNickel schema.not false})",
          # { type, ..rest } if std.typeof type == '"Array" => type |> std.array.map (fun e => { type = "%{e}" }) |> OneOf,
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
    schemaStr,

  GetRef
    | (String -> String)
    | default
    = fun ref =>
      let ref = std.string.split "/" ref in
      ref
      |> match {
        ["#", "definitions", ..rest] => std.trace "ref %{std.array.first rest}" std.array.first rest,
        ["#", "defs", ..rest] => std.array.first rest
      },
}
in
Converters
