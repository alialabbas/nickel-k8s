let lib = import "lib.ncl" in

let rec _to_merge_form
# : Array { field : String, value : String, nested : Array { field : String, value : String, nested : Dyn } } -> _
= fun specs value =>
  std.array.fold_right
    (fun e acc =>
      let result = acc in
      let parentPath = std.string.split "." e.field in
      let val = lib.records.get_value_at_path parentPath result in
      let val_map =
        val
        |> match {
          'Found val => lib.k8s.from_list_to_map e.value val,
          _ => val
        }
      in
      let result = lib.records.update_value_at_path parentPath val_map result in
      let inner =
        lib.records.get_value_at_path parentPath result
        |> match {
          'Found val => val,
          _ => {}
        }
      in
      std.array.fold_right
        (fun n acc =>
          std.array.fold_right
            (fun e _acc =>
              let path = parentPath @ [e, n.field] in
              let value = lib.records.get_value_at_path path acc in
              let value_map =
                value
                |> match {
                  'Found val => lib.k8s.from_list_to_map "%{n.value}" val,
                  _ => value
                }
              in
              lib.records.update_value_at_path path value_map acc
            )
            result
            (std.record.fields inner)
        )
        result
        e.nested
    )
    value
    specs
in
let _from_merge_form
  | doc "Convert a resource back from its mergable-form"
  # : Array { field : String, value : String, nested : Array { field : String, value : String, nested : Dyn } } -> String
  = fun specs value =>
    std.array.fold_right
      (fun e acc =>
        let parentPath = std.string.split "." e.field in
        let result = acc in
        let inner =
          lib.records.get_value_at_path parentPath result
          |> match {
            'Found val => val,
            _ => {}
          }
        in
        let result =
          std.array.fold_right
            (fun n acc =>
              std.array.fold_right
                (fun e _acc =>
                  let path = parentPath @ [e, n.field] in
                  let value =  lib.records.get_value_at_path path acc in
                  let value_map =
                    value
                    |> match {
                      'Found val => lib.k8s.from_map_to_list "%{n.value}" val,
                      _ => value
                    }
                  in
                  lib.records.update_value_at_path path value_map acc
                )
                result
                (std.record.fields inner)
            )
            result
            e.nested
        in
        let val = lib.records.get_value_at_path parentPath result in
        let val_map =
          val
          |> match {
            'Found val => lib.k8s.from_map_to_list "%{e.value}" val,
            _ => val
          }
        in
        let result = lib.records.update_value_at_path parentPath val_map result in
        result
      )
      value
      specs
  in
{
  to_merge_form = _to_merge_form,
  from_merge_form = _from_merge_form,
}
