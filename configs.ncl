let lib = import "lib.ncl" in
let ValidConfigKey = fun key => std.string.is_match "^[-_.0-9a-zA-Z]*$" key in
let ConfigData =
  std.contract.from_predicate (fun data =>
    std.record.to_array data
    |> std.array.all (fun singleRecord => ValidConfigKey singleRecord.field)
  )
in
{
  v1 = {
    Namespace = {
      metadata | lib.k8s.ResourceMetadata,
      ..
    },
    Secret = {
      apiVersion | String | force = "v1",
      kind | String | force = "Secret",
      metadata | lib.k8s.ResourceMetadata,
      type | String | optional, # TODO: this could be done client side
      immutable | Bool | optional,
      data | ConfigData | { _ : String } | optional,
      stringData | ConfigData | { _ : String } | optional,
      ..
    },
    ConfigMap = {
      apiVersion | String | force = "v1",
      kind | String | force = "ConfigMap",
      metadata | lib.k8s.ResourceMetadata,
      immutable | Bool | optional,
      data | ConfigData | { _ : String } | optional,
      binaryData | ConfigData | { _ : String } | optional,
      ..
    },
    PersistentVolumeClaim = {
      apiVersion | String | force = "v1",
      kind | String | force = "PersistentVolumeClaim",
      metadata | lib.k8s.ResourceMetadata,
      spec
        | {
          accessModes
            | Array (std.contract.Sequence [std.enum.TagOrString, [| 'ReadWriteOnce, 'ReadOnlyMany, 'ReadWriteMany, 'ReadWriteOncePod |]]),
          dataSource | { apiGroup | String, kind | String, name | lib.k8s.Name } | optional,
          dataSourceRef | { apiGroup | String, kind | String, name | lib.k8s.Name, namespace | lib.k8s.Name } | optional,
          resources
            | {
              claims | Array { name | String } | optional,
              limits | { storage | lib.k8s.Resource } | optional,
              requests | { storage | lib.k8s.Resource } | optional,
            },
          selector | lib.k8s.LabelSelector | optional,
          storageClassName | String | optional,
          volumeName | String | optional,
        },
      ..
    },
  },
}
