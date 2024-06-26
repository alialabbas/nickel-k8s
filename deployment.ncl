let { Metadata, ResourceMetadata, LabelSelector, WorkloadSelector, .. } = import "metadata.ncl" in
let { Numbers, .. } = import "types.ncl" in
let { Kube, ApiGroups, .. } = import "kube.ncl" in
let { PodSpec, Pod, .. } = import "podspec.ncl" in

let OnlyIfRollingUpdate = fun other_field =>
  std.contract.from_predicate
    (
      fun value =>
        if std.record.has_field "type" other_field then
          ((std.string.from_enum other_field.type) == "RollingUpdate")
        else
          true # kube by rolling strategy is RollingUpdate
    )
in
let JobSpec = {
  activeDeadlineSeconds | std.number.PosNat | optional,
  backoffLimit | std.number.PosNat | optional,
  completions | std.number.PosNat | optional,
  completionMode | String | optional, # TODO: enum
  manualSelector | Bool | optional,
  parallelism | std.number.PosNat | optional,
  selector | LabelSelector | optional,
  suspend | Bool | optional,
  ttlSecondsAfterFinished | std.number.PosNat | optional,
  template
    | {
      metadata | Metadata | optional,
      spec | PodSpec,
    },
  podFailurePolicy
    | {
      rules
        | {
          action | std.enum.TagOrString | [| 'FailJob, 'Ignore, 'Count |],
          # TODO: container name here can be null
          # TODO: In can't use 0 in values
          # TODO: MinItems 1 for the number array
          # TODO: At most 255
          onExitCodes
            | { containerName | Kube.Name, operator | std.enum.TagOrString | [| 'In, 'NotIn, |], values | Array Number, },
          onPodConditions | Array { status | String | optional, type | String, } | optional,
        }
        | optional,
    }
    | optional,
}
in
let rec SelectorValidatorContract
  | doc m%"This contract implement the server side validation for ensuring a workload, deployment, statefulset, etc are able to select the pods they are creating and managing them"%
  = fun template label value =>
    let podLabels = template.metadata.labels |> std.record.to_array in
    let matchLabelsContract = fun label value =>
      let errMsg = podLabels |> std.array.fold_right (fun e acc => m%"{ %{e.field} = %{e.value} }"% ++ " " ++ acc) "" in
      let matchSelectors = value.matchLabels |> std.record.to_array in
      if matchSelectors
      |> std.array.all
        (
          fun e =>
            if !std.array.elem e podLabels then
              std.contract.blame_with_message "matchLabel should match at least one of the following [%{errMsg}]" label
            else
              true
        ) then
        value
      else
        std.contract.blame label
    in

    let matchExpressionContract = fun label value =>
      let expressions = value.matchExpressions in
      let existErrMsg = podLabels |> std.array.fold_right (fun e acc => e.field ++ " " ++ acc) "" in
      let inErrorMsg = podLabels |> std.array.fold_right (fun e acc => m%"{ %{e.field} = %{e.value} }"% ++ " " ++ acc) "" in
      if !(
        expressions
        |> std.array.all
          (
            fun expr =>
              expr.operator
              |> match {
                'In =>
                  # key should be in labels and one of the listed values should match the label value
                  if !std.array.any (fun v => std.array.elem { field = expr.key, value = v } podLabels) expr.values then
                    std.contract.blame_with_message "In Expression need to match one of the following [%{inErrorMsg}]" label
                  else
                    true,
                'NotIn =>
                  # Key not matching is fine, but if the key matches, we need to get the value out and check we are not excluding a value listed in the original label set
                  let podLabels = template.metadata.labels in
                  if (std.record.has_field expr.key podLabels) && (std.array.elem (std.record.get expr.key podLabels) expr.values) then
                    std.contract.blame_with_message m%"NotIn expression can't exclude value from the pod labels"% label
                  else
                    true,
                'Exists =>
                  if !std.array.any (fun e => e.field == expr.key) podLabels then
                    std.contract.blame_with_message m%"PodLabels doesn't have label key %{expr.key}, only one of the following are possible [%{existErrMsg}]"% label
                  else
                    true,
                'DoesNotExist =>
                  if std.array.any (fun e => e.field == expr.key) podLabels then
                    std.contract.blame_with_message m%"DoesNotExist can't use %{expr.key}, since this is one of the pod template values [%{existErrMsg}] and the workload won't be able to selecto the created pods"% label
                  else
                    true,
                _ => std.contract.blame_with_message m%"Invalid operator %{expr.operator}"%,
              }
          )
      ) then
        std.contract.blame_with_message "Uncaught error, shuold never reach this point" label
      else
        value
    in

    value
    |> match {
      { matchExpressions } => std.contract.apply matchExpressionContract label value,
      { matchLabels } => std.contract.apply matchLabelsContract label value,
      { matchExpressions, matchLabels } => std.contract.apply (std.contract.Sequence [matchLabelsContract, matchExpressionContract]) label value,
      _ => std.contract.blame_with_message "No matching selector found" label,
    }
  in
{
  Deployment = {
    metadata | ResourceMetadata,
    apiVersion = "apps/v1",
    kind = "Deployment",
    spec
      | {
        minReadySeconds | std.number.PosNat | optional,
        paused | Bool | optional,
        progressDeadlineSeconds | std.number.PosNat | optional,
        replicas | std.number.PosNat | optional,
        revisionHistoryLimit | std.number.PosNat | optional,
        selector | WorkloadSelector | SelectorValidatorContract template,
        strategy
          | {
            type | std.enum.TagOrString | [| 'RollingUpdate, 'Recreate |] | optional,
            rollingUpdate
              | {
                maxSurge | OnlyIfRollingUpdate strategy | Numbers.NumberOrPercentage | optional,
                maxUnavailable | OnlyIfRollingUpdate strategy | std.number.Nat | optional,
              }
              | std.contract.from_predicate (fun val => !(val.maxSurge == 0 && val.maxUnavailable == 0)) # TODO: should these be scoped internally into a predicates record
              | optional
          }
          | optional,
        template
          | {
            metadata | Metadata,
            spec | PodSpec,
          },
      },
  },

  StatefulSet = {
    metadata | ResourceMetadata,
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    spec
      | {
        minReadySeconds | std.number.PosNat | optional,
        ordinals | { start | std.number.PosNat } | optional,
        replicas | std.number.PosNat | optional,
        revisionHistoryLimit | std.number.PosNat | optional,
        podManagementPolicy | std.enum.TagOrString | [| 'Parallel, 'OrderedReady |] | optional,
        selector | WorkloadSelector | SelectorValidatorContract template,
        serviceName | Kube.Name,
        template = {
          metadata | Metadata,
          spec | PodSpec
        },
        persistentVolumeClaimRetentionPolicy
          | {
            whenDeleted | std.enum.TagOrString | [| 'Delete, 'Retain |] | optional,
            whenScaled | std.enum.TagOrString | [| 'Delete, 'Retain |] | optional,
          }
          | optional,
        updateStrategy
          | {
            type | std.enum.TagOrString | [| 'RollingUpdate, 'OnDelete |] | optional,
            rollingUpdate # TODO: Lock this similar to deployment spec
              | {
                partition | std.number.Nat | optional,
                maxUnavailable | Numbers.NumberOrPercentage | optional
              }
              | optional,
          }
          | optional,
        volumeClaimTemplates | Array { .. } | optional, # TODO: model me with pvc template
      },
  },

  Pod = {
    metadata | ResourceMetadata,
    apiVersion = "v1",
    kind = "Pod",
    spec | PodSpec
  },

  CronJob
    | doc "CronJob represents the configuration of a single cron job."
    = {
      metadata | ResourceMetadata,
      apiVersion = "batch/v1",
      kind = "CronJob",
      spec
        | {
          concurrencyPolicy | String | optional,
          failedJobsHistoryLimit | std.number.PosNat | optional,
          schedule | String, # TODO: validation,
          startingDeadline | std.number.PosNat | optional,
          successfulJobsHistoryLimit | std.number.PosNat | optional,
          suspend | Bool | optional,
          timeZone | String | optional, # timezone contract later
          jobTemplate | { metadata | Metadata | optional, spec | JobSpec },
        },
    },

  Job = {
    apiVersion = "batch/v1",
    kind = "Job",
    metadata | ResourceMetadata,
    spec | JobSpec,
  },

  DaemonSet = {
    apiVersion = "apps/v1",
    kind = "DaemonSet",
    metadata | ResourceMetadata,
    spec
      | {
        selector | WorkloadSelector | SelectorValidatorContract template,
        updateStrategy | { .. } | optional,
        template | { spec | PodSpec, metadata | Metadata | optional },
      },
  },
} | ApiGroups
