let config = import "config-descriptor.json" in
let lib = import "../../lib.ncl" in
let Nullable = fun contract =>
  std.contract.custom (fun label value =>
    if value == null then
    # no point in handling null during aggregation, empty array won't yield anything
      'Ok []
    else
      std.contract.check (contract) label value
  )
in
let rec Model = {
  Kind | String | optional,
  Name | String | optional,
  Required | Bool | optional,
  Desc | String | optional,
  Block | Nullable Model | optional,
  BlockDesc | String | optional,
  Inline | Bool | optional,
  FieldDesc | String | optional,
  FieldDefault | Dyn | optional,
  FieldExample | Dyn | optional,
  Element | Dyn | optional,
  Root | Bool | optional,
  FieldValue | Dyn | optional,
  FieldDefaultValue | Dyn | optional,
  FieldFlag | String | optional,
  FieldType | String | optional,
  FieldCategory | String | optional,
  FieldElement | Model | optional,
  Entries | Nullable (Array Model) | optional,
  FlagsPrefix | String | optional,
  FlagsPrefixes | Dyn | optional,
}
in
let has_enum = fun desc =>
  if std.string.is_match "^.* are: .*$" desc then
    true
  else
    false
in
let parse_enums = fun desc =>
  let values =
    std.string.split ":" desc
    |> std.array.last
    |> std.string.split ","
    |> std.array.map (fun e => std.string.trim e)
  in
  let last_value = std.array.last values |> std.string.split "." |> std.array.first in
  let values = std.array.drop_last values |> (@) [last_value] in
  lib.enum.ArrayEnum values
in
let rec to_nickel_contract | Array Model -> Dyn = fun cfg =>
  let process | Model -> Dyn = fun m =>
    let enum =
      if has_enum m.FieldDesc then
        parse_enums m.FieldDesc
      else
        'None
    in
    let rec to_type = match {
      "string" => String,
      "strings" => String,
      "int" => std.number.Integer,
      "float" => Number,
      "boolean" => Bool,
      "duration" => String, # TODO: need a proper duration contract `1s, `1m`, `1us`, etc
      "durations" => String,
      "slice" => Array (to_nickel_contract m.fieldElement.blockEntries),
      v if std.string.is_match "list of .*" v => let Elem = std.string.split " " v |> std.array.last |> to_type in Array Elem,
      _ => Dyn,
    }
    in
    let Type = if enum == 'None then to_type m.FieldType else std.contract.Sequence [to_type m.FieldType, enum] in
    if m.Required then
      { "%{m.Name}" | Type }
    else
      { "%{m.Name}" | Type | optional }
  in
  std.array.fold_right
    (fun e acc =>
      if e.Kind == "field" || e.Kind == "slice" then
        acc & (process e)
      else if std.record.has_field "Block" e && e.Block != null then
        # Inlined struct don't have a name
        if e.Name == "" then
          acc & (to_nickel_contract e.Block.Entries)
        else if e.Required then
          acc & { "%{e.Name}" | (to_nickel_contract e.Block.Entries) }
        else
          acc & { "%{e.Name}" | (to_nickel_contract e.Block.Entries) | optional }
      else
        # TODO: this need to do something more than this
        acc
    )
    {}
    cfg
in
to_nickel_contract config.Entries
