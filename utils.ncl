let lib = import "Contracts.ncl" in
{
  kube = {
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
              if e.field | lib.IsContract std.string.NumberLiteral then
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

  records = {
    get_value_at_path
    # : Array String -> { _ : Dyn } -> [| 'NotFound, 'Found |]
    = fun path value =>
      let leftOverPath = std.array.slice 1 (std.array.length path) path in
      let head = std.array.first path in
      # if we have anything left, recruse
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
  }
}
