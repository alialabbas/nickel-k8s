let lib = import "Contracts.ncl" in
# TODO: this somehow fails on the core value by itself
let from_map_to_list
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
    }
  in

let from_list_to_map = fun key value =>
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
  }
in

let rec get_value_at_path
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
    'Found value."%{head}"
in

let rec update_value_at_path
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
      std.record.update head updateVal value
  in
let originalPod = fun pod =>
  let result = pod in

  let inner =
    get_value_at_path ["metadata", "ownerReferences", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["metadata", "ownerReferences", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["metadata", "ownerReferences", ] val_map result in
  let inner =
    get_value_at_path ["spec", "volumes", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "volumes", e, "ephemeral.volumeClaimTemplate.metadata.ownerReferences", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "uid" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["spec", "volumes", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "volumes", ] val_map result in
  let inner =
    get_value_at_path ["spec", "topologySpreadConstraints", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["spec", "topologySpreadConstraints", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "topologySpreadConstraints", ] val_map result in
  let inner =
    get_value_at_path ["spec", "schedulingGates", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["spec", "schedulingGates", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "schedulingGates", ] val_map result in
  let inner =
    get_value_at_path ["spec", "resourceClaims", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["spec", "resourceClaims", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "resourceClaims", ] val_map result in
  let inner =
    get_value_at_path ["spec", "initContainers", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "initContainers", e, "resources.claims", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "initContainers", e, "volumeMounts", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "mountPath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "initContainers", e, "volumeDevices", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "devicePath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "initContainers", e, "ports", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "containerPort" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "initContainers", e, "env", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["spec", "initContainers", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "initContainers", ] val_map result in
  let inner =
    get_value_at_path ["spec", "imagePullSecrets", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["spec", "imagePullSecrets", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "imagePullSecrets", ] val_map result in
  let inner =
    get_value_at_path ["spec", "hostAliases", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["spec", "hostAliases", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "hostAliases", ] val_map result in
  let inner =
    get_value_at_path ["spec", "ephemeralContainers", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "ephemeralContainers", e, "resources.claims", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "ephemeralContainers", e, "volumeMounts", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "mountPath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "ephemeralContainers", e, "volumeDevices", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "devicePath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "ephemeralContainers", e, "ports", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "containerPort" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "ephemeralContainers", e, "env", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["spec", "ephemeralContainers", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "ephemeralContainers", ] val_map result in
  let inner =
    get_value_at_path ["spec", "containers", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "containers", e, "resources.claims", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "containers", e, "volumeMounts", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "mountPath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "containers", e, "volumeDevices", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "devicePath" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "containers", e, "ports", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "containerPort" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["spec", "containers", e, "env", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "name" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["spec", "containers", ] result in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["spec", "containers", ] val_map result in
  let inner =
    get_value_at_path ["status", "containerStatuses", "resources", "claims", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "containerStatuses", "resources", "claims", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "containerStatuses", "resources", "claims", ] val_map result in
  let inner =
    get_value_at_path ["status", "containerStatuses", "volumeMounts", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "containerStatuses", "volumeMounts", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "containerStatuses", "volumeMounts", ] val_map result in
  let inner =
    get_value_at_path ["status", "containerStatuses", "allocatedResourcesStatus", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["status", "containerStatuses", "allocatedResourcesStatus", e, "resources", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "resourceID" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["status", "containerStatuses", "allocatedResourcesStatus", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "containerStatuses", "allocatedResourcesStatus", ] val_map result in
  let inner =
    get_value_at_path ["status", "ephemeralContainerStatuses", "resources", "claims", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "ephemeralContainerStatuses", "resources", "claims", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "ephemeralContainerStatuses", "resources", "claims", ] val_map result in
  let inner =
    get_value_at_path ["status", "ephemeralContainerStatuses", "volumeMounts", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "ephemeralContainerStatuses", "volumeMounts", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "ephemeralContainerStatuses", "volumeMounts", ] val_map result in
  let inner =
    get_value_at_path ["status", "ephemeralContainerStatuses", "allocatedResourcesStatus", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["status", "ephemeralContainerStatuses", "allocatedResourcesStatus", e, "resources", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "resourceID" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["status", "ephemeralContainerStatuses", "allocatedResourcesStatus", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "ephemeralContainerStatuses", "allocatedResourcesStatus", ] val_map result in
  let inner =
    get_value_at_path ["status", "initContainerStatuses", "resources", "claims", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "initContainerStatuses", "resources", "claims", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "initContainerStatuses", "resources", "claims", ] val_map result in
  let inner =
    get_value_at_path ["status", "initContainerStatuses", "volumeMounts", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "initContainerStatuses", "volumeMounts", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "initContainerStatuses", "volumeMounts", ] val_map result in
  let inner =
    get_value_at_path ["status", "initContainerStatuses", "allocatedResourcesStatus", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let result =
    std.array.fold_right
      (fun e acc =>
        let path = ["status", "initContainerStatuses", "allocatedResourcesStatus", e, "resources", ] in
        let value = get_value_at_path path result in
        let value_map =
          value
          |> match {
            'Found val => from_map_to_list "resourceID" val,
            _ => value
          }
        in
        update_value_at_path path value_map acc
      )
      result
      (std.record.fields inner)
  in
  let val = get_value_at_path ["status", "initContainerStatuses", "allocatedResourcesStatus", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "initContainerStatuses", "allocatedResourcesStatus", ] val_map result in
  let inner =
    get_value_at_path ["status", "resourceClaimStatuses", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "resourceClaimStatuses", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "resourceClaimStatuses", ] val_map result in
  let inner =
    get_value_at_path ["status", "podIPs", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "podIPs", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "podIPs", ] val_map result in
  let inner =
    get_value_at_path ["status", "conditions", ] result
    |> match {
      'Found val => val,
      _ => {}
    }
  in

  let val = get_value_at_path ["status", "conditions", ] pod in
  let val_map =
    val
    |> match {
      'Found val => from_map_to_list "name" val,
      _ => val
    }
  in
  let result = update_value_at_path ["status", "conditions", ] val_map result in

  result
in
originalPod {
  spec = {
    containers = {
      test = {
        env = { deploment = { value = "test", }, },
        image = "test",
      },
    },
  },
}
