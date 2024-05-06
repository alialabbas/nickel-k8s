let { Kube, .. } = import "kube.ncl" in
let validLabel
  | doc "label and annotation validation, alphanumeric, _, - or ."
  = fun str =>
    std.string.is_match
      "^[a-zA-Z0-9]([-_/\\.a-zA-Z0-9]*[a-zA-Z0-9]\\/?[a-zA-Z0-9]*[a-zA-Z0-9]?)?$"
      # "[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*"
      str
  in
let labelAnnotationContract =
  std.contract.from_predicate
    (
      fun val =>
        std.array.all
          (fun record => (validLabel record.field) && (validLabel record.value))
          (std.record.to_array val)
    )
in
let annotationsContract =
  std.contract.from_predicate
    (
      fun val =>
        std.array.all
          (fun record => (validLabel record.field))
          (std.record.to_array val)
    )
in
let OnlyWhenInOrNotIn
  | doc "Selector values need to be empty if the operator is Exist or DoesNotExist, and In or NotIn, values can't be empty"
  = fun operator label value =>
    operator
    |> match {
      'In => value,
      'NotIn => value,
      'Exists => std.contract.blame_with_message "Exists and DoesNotExist can't have values defined" label,
      'DoesNotExist => std.contract.blame_with_message "Exists and DoesNotExist can't have values defined" label,
      _ => std.contract.blame_with_message m%"Unkown Operator %{std.string.from_enum operator}"%,
    }
  in
{
  Metadata
    | doc "ObjectMeta is metadata that all persisted resources must have, which includes all objects users must create."
    = {
      labels | labelAnnotationContract | optional,
      annotations | annotationsContract | optional,
      name | Kube.Name | optional,
      namespace | Kube.Name | optional,
    },
  ResourceMetadata | doc "Extension of Metadata, includes metadata.name, the other one is used in embedded resources" = { name | Kube.Name } & Metadata,
  ValidLabel = std.contract.from_predicate (fun val => validLabel val),
  Labels = labelAnnotationContract,

  LabelSelector = {
    matchExpressions
      | Array {
        key | ValidLabel,
        operator | std.enum.TagOrString | [| 'In, 'NotIn, 'Exists, 'DoesNotExist |],
        values | Array ValidLabel | optional | OnlyWhenInOrNotIn operator,
      }
      | optional,
    matchLabels | Labels | optional,
  },
  WorkloadSelector
    | doc m%%"Similar to LabelSelector except that it is enforcing the minimal required properties for when a selector object used in workload
e.g deploymentspec.selector requires matchExpressions or matchLabels to be specified
"%%
    = fun label value =>
      if std.is_record value
      && (std.record.has_field "matchLabels" value || std.record.has_field "matchExpressions" value) then
        value | LabelSelector
      else
        %blame% label,
}
