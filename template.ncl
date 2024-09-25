let print_array : Array String -> String
  = fun arr =>
    std.array.fold_left (fun acc e => acc ++ e ++ ",") "[" arr ++ "]"
  in
let templateToMergable
  | doc "Template generate a conversion function from each source based on its spec"
  : String -> Array { field : String, value : String, nested : Array { field : String, value : String } } -> String
  = fun resource specs =>
    let lowerCaseResource = std.string.lowercase resource in
    m%"
let mergable%{resource} = fun %{lowerCaseResource} =>
  let result = %{lowerCaseResource} in
  %{
    let aggregator
      : { field :String, value : String, nested : Array { field : String, value: String }} -> String -> String
      = fun e acc =>
      let parentPath = std.string.split "." e.field |> std.array.map(fun e => "\"%{e}\"") in
      let paramName = std.array.last parentPath in
      let pathAsString = print_array parentPath in
      acc ++ "\n" ++ m%"
        let val = get_value_at_path %{pathAsString} result in
        let val_map =
          val
          |> match {
            'Found val => from_list_to_map "name" val,
            _ => val
          }
        in
        let result = update_value_at_path %{pathAsString} val_map result in
        %{
            m%"
              let inner = get_value_at_path %{pathAsString} result |> match {
                'Found val => val,
                _ => {}
              } in
              %{std.array.fold_right(fun e acc => acc ++ "\n" ++ m%"
              let result =
                std.array.fold_right
                  (fun e acc =>
                    let path = %{print_array (parentPath @ ["e"] @ ["\"%{e.field}\""])} in
                    let value = get_value_at_path path result in
                    let value_map =
                      value
                      |> match {
                        'Found val => from_list_to_map "%{e.value}" val,
                        _ => value
                      }
                    in
                    update_value_at_path path value_map acc
                  )
                  result
                  (std.record.fields inner)
                in
              "%) "" e.nested}
            "%
          }
      "%
      in
    std.array.fold_right(aggregator) "" specs
  }

  result,
"%
  in
let templateFromMergable
  | doc "Convert a resource back from its mergable-form"
  : String -> Array { field : String, value : String, nested : Array { field : String, value : String } } -> String
  = fun resource specs =>
    let lowerCaseResource = std.string.lowercase resource in
    m%"
let original%{resource} = fun %{lowerCaseResource} =>
  let result = %{lowerCaseResource} in
  %{
    let aggregator
      : { field :String, value : String, nested : Array { field : String, value: String }} -> String -> String
      = fun e acc =>
      let parentPath = std.string.split "." e.field |> std.array.map(fun e => "\"%{e}\"") in
      let paramName = std.array.last parentPath in
      let pathAsString = print_array parentPath in
      acc ++ "\n" ++ m%"
        %{
            m%"
              let inner = get_value_at_path %{pathAsString} result |> match {
                'Found val => val,
                _ => {}
              } in
              %{std.array.fold_right(fun e acc => acc ++ "\n" ++ m%"
              let result =
                std.array.fold_right
                  (fun e acc =>
                    let path = %{print_array (parentPath @ ["e"] @ ["\"%{e.field}\""])} in
                    let value = get_value_at_path path result in
                    let value_map =
                      value
                      |> match {
                        'Found val => from_map_to_list "%{e.value}" val,
                        _ => value
                      }
                    in
                    update_value_at_path path value_map acc
                  )
                  result
                  (std.record.fields inner)
                in
              "%) "" e.nested}
            "%
          }
        let val = get_value_at_path %{pathAsString} result in
        let val_map =
          val
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => val
          }
        in
        let result = update_value_at_path %{pathAsString} val_map result in
      "%
      in
    std.array.fold_right(aggregator) "" specs
  }

  result,
"%
  in
{
  ListToMap = templateToMergable,
  MapToList = templateFromMergable,
}
