let { ResourceMetadata, LabelSelector, .. } = import "metadata.ncl" in
let { Kube, ApiGroups, .. } = import "kube.ncl" in
let ValidConfigKey = fun key => std.string.is_match "^[-_.0-9a-zA-Z]*$" key in
let ConfigData =
  std.contract.from_predicate
    (
      fun data =>
        std.record.to_array data
        |> std.array.all (fun singleRecord => ValidConfigKey singleRecord.field)
    )
in
{
  Secret = {
    apiVersion | String | force = "v1",
    kind | String | force = "Secret",
    metadata | ResourceMetadata,
    type | String | optional, # TODO: this could be done client side
    immutable | Bool | optional,
    data | ConfigData | { _ : String } | optional,
    stringData | ConfigData | { _ : String } | optional,
    ..
  },

  ConfigMap = {
    apiVersion | String | force = "v1",
    kind | String | force = "ConfigMap",
    metadata | ResourceMetadata,
    immutable | Bool | optional,
    data | ConfigData | { _ : String } | optional,
    binaryData | ConfigData | { _ : String } | optional,
    ..
  },

  PersistentVolumeClaim = {
    apiVersion | String | force = "v1",
    kind | String | force = "PersistentVolumeClaim",
    metadata | ResourceMetadata,
    spec
      | {
        accessModes
          | Array (std.contract.Sequence [std.enum.TagOrString, [| 'ReadWriteOnce, 'ReadOnlyMany, 'ReadWriteMany, 'ReadWriteOncePod |]]),
        dataSource | { apiGroup | String, kind | String, name | Kube.Name } | optional,
        dataSourceRef | { apiGroup | String, kind | String, name | Kube.Name, namespace | Kube.Name } | optional,
        resources
          | {
            claims | Array { name | String } | optional,
            limits | { storage | Kube.Resource } | optional,
            requests | { storage | Kube.Resource } | optional,
          },
        selector | LabelSelector | optional,
        storageClassName | String | optional,
        volumeName | String | optional,
      },
      ..
  },
} | ApiGroups
