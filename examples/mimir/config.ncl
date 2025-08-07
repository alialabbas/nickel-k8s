let config = import "config-descriptor.json" in
let lib = import "../../lib.ncl" in
let rec Model = {
  kind | String | optional,
  name | String | optional,
  required | Bool | optional,
  desc | String | optional,
  fieldValue | Dyn | optional,
  fieldDefaultValue | Dyn | optional,
  fieldFlag | String | optional,
  fieldType | String | optional,
  fieldCategory | String | optional,
  fieldElement | Model | optional,
  blockEntries | Array Model | optional,
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
      if has_enum m.desc then
        parse_enums m.desc
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
    let Type = if enum == 'None then to_type m.fieldType else std.contract.Sequence [to_type m.fieldType, enum] in
    if m.required then
      { "%{m.name}" | Type }
    else
      { "%{m.name}" | Type | optional }
  in
  std.array.fold_right
    (fun e acc =>
      if e.kind == "field" then
        acc & (process e)
      else if std.record.has_field "blockEntries" e then
        if e.required then
          acc & { "%{e.name}" | (to_nickel_contract e.blockEntries) }
        else
          acc & { "%{e.name}" | (to_nickel_contract e.blockEntries) | optional }
      else
        # TODO: this need to do something more than this
        acc
    )
    {}
    cfg
in
to_nickel_contract config.blockEntries
