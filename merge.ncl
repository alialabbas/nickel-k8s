# Generates a record of ToMergable and FromMergable record for all resources in a swagger
{
  Input = {},

  Output =
    let get_ref
      | (String -> String)
      = fun ref =>
        let ref = std.string.split "/" ref in
        ref
        |> match {
          ["#", "definitions", ..rest] => std.array.first rest,
          ["#", "defs", ..rest] => std.array.first rest
        }
      in

    let rec get_paths = fun value =>
      value
      |> std.record.to_array
      |> std.array.fold_right
        (fun e acc =>
          # we always have to expand the ref first because it's value is string but technically it references a record we want to inline in the final result
          if e.field == "$ref" then
            acc
            @ (get_paths Input.definitions."%{get_ref e.value}")
          else if std.typeof e.value == 'Record
          && (std.record.has_field "x-kubernetes-list-type" e.value)
          && (e.value.x-kubernetes-list-type == "map") then
            [
              {
                field = e.field,
                value = (std.array.first e.value.x-kubernetes-list-map-keys),
                nested = (
                  std.array.map
                    (fun p =>
                      { field = p.field, value = p.value, nested = [] }
                    )
                    (get_paths e.value)
                )
              }
            ]
            @ acc
            # There has to be a faster way to do this
            # we are recursing on non-needed data, ideally if we are in a schema, we just go over the properties and so on
            # We are only interested in arrays which what we do above implicitly.
            # Here, we should only be concerned with what can truly give us a sub schema of an array, i.e.... properties that might be an array
          else if std.typeof e.value != 'Record then
            acc
          else
            acc
            @ (
              std.array.map
                (fun p =>
                  # TODO: this need to skip if this is a schema only. Figure out a way to operate at the schema level
                  # TODO: check type for each object and items, that has to be a string and string only
                  # NOTE: this is needed so we don't include the schema path in the actual object, those refert to object and array schemas
                  if e.field == "properties" || e.field == "items" then
                    p
                  else
                    { field = "%{e.field}." ++ p.field, value = p.value, nested = std.record.get_or "nested" [] p }
                )
                (get_paths e.value)
            )
        )
        []
    in
    (
      # TODO: is there anyway to speed this up
      # Two issues to think about
      # finding the first anchor, i.e. the first map-able array
      # then that array itself could hoist another map-able array and so on.
      # possible to merge them so that the output deals with a flatten object but that would assume structure that i would rather avoid
      # Input.definitions
      (std.record.get_or "definitions" {} Input)
      |> std.record.filter (fun e v => std.record.has_field "x-kubernetes-group-version-kind" v)
      |> std.record.filter (fun e v => !std.string.contains "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1" e)
      |> std.record.to_array
      |> std.array.fold_right
        (fun e acc =>
          let groupDef = std.array.first e.value.x-kubernetes-group-version-kind in
          # pull a single schema out and try to debug it. Ideally a single walk over the schmea
          # i suspect we are iterating on many values and expanding the stack over and over
          let paths = get_paths e.value in
          if groupDef.group == "" then
            { "%{groupDef.version}"."%{groupDef.kind}" = paths } & acc
          else
            { "%{groupDef.group}"."%{groupDef.version}"."%{groupDef.kind}" = paths } & acc
        )
        {}
      # TODO: make this a method and it expect the schema from a singualr place
      # one for k8s schemas and one for CRDs themselves since each needs to be handled uniquely
      # get_paths ((std.array.first (std.array.at 7 Input).spec.versions).schema.openAPIV3Schema)
    )
}
