let lib = import "lib.ncl" in

let deployment_rolling_strategy = fun other_field =>
  std.contract.custom (fun label value =>
    other_field
    |> match {
      { type, .. } if type == 'Recreate => 'Error { message = "Recreate Strategy can't specify maxUnavailable or maxSurge" },
      _ => 'Ok value,
    }
  )
in
# TODO: this needs some simplification
# potentially some of this stuff could be extracted out for other crds that might need to use some sort of label selection
# also, maybe not pass template and instead internal contracts would have labels only
# The outer here is just a realization of the contract, i.e. we leave this to the caller to decide how to wrap the contract.
# now what is left is just cleaning up the contract
let rec SelectorValidatorContract = fun template label value =>
  let podLabels = template.metadata.labels |> std.record.to_array in
  let matchLabelsContract = fun label value =>
    let errMsg = podLabels |> std.array.fold_right (fun e acc => m%"{ %{e.field} = %{e.value} }"% ++ " " ++ acc) "" in
    let matchSelectors = value.matchLabels |> std.record.to_array in
    if matchSelectors
    |> std.array.all (fun e =>
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
    let existErrMsg =
      podLabels
      |> std.array.fold_right
        (fun e acc => e.field ++ " " ++ acc
        )
        ""
    in
    let inErrorMsg =
      podLabels
      |> std.array.fold_right
        (fun e acc => m%"{ %{e.field} = %{e.value} }"% ++ " " ++ acc
        )
        ""
    in
    if !(
      expressions
      |> std.array.all (fun expr =>
        expr.operator
        |> match {
          "In" =>
            # key should be in labels and one of the listed values should match the label value
            # somehow, somehow, values here is a function
            if !std.array.any (fun v => std.array.elem { field = expr.key, value = v } podLabels) expr.values then
              std.contract.blame_with_message "In Expression need to match one of the following [%{inErrorMsg}]" label
            else
              true,
          "NotIn" =>
            # Key not matching is fine, but if the key matches, we need to get the value out and check we are not excluding a value listed in the original label set
            let podLabels = template.metadata.labels in
            if (std.record.has_field expr.key podLabels) && (std.array.elem (std.record.get expr.key podLabels) expr.values) then
              std.contract.blame_with_message m%"NotIn expression can't exclude value from the pod labels"% label
            else
              true,
          "Exists" =>
            if !std.array.any (fun e => e.field == expr.key) podLabels then
              std.contract.blame_with_message m%"PodLabels doesn't have label key %{expr.key}, only one of the following are possible [%{existErrMsg}]"% label
            else
              true,
          "DoesNotExist" =>
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

let fieldRefContract =
  let validFieldRefs = [
    "metadata.name",
    "metadata.namespace",
    "metadata.labels",
    "metadata.annotations",
    "spec.nodeName",
    "spec.serviceAccountName",
    "status.hostIP",
    "status.podIP",
    "status.podIPs",
  ]
  in
  fun label val =>
    if (
      (
        std.is_string val
        && std.string.is_match "^metadata\\.(labels|annotations)\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" val
      )
      || std.array.elem val validFieldRefs
    ) then
      val
    else
      std.contract.blame_with_message "invalid metadata.labels or metadata.annotations name" label
in
let ResourceRefs = [|
  '"limits.cpu",
  '"limits.memory",
  '"requests.cpu",
  '"requests.memory"
|]
in
let AllPreds = fun preds =>
  std.contract.from_predicate (fun record => std.array.fold_right (fun pred acc => pred record && acc) true preds)
in
# TODO: doable with pattern matching
let OnlyOneOf # this will be higher order func called on the reocrd
  | doc "simple XOR implementation for fields at the same root level"
  = fun fields =>
    (fun record =>
      # TODO: either we do this here or we rely on better composition of these complex contracts so that we are able to say this or that exteranlly
      if record == null then
        true
      else
        # can't use has_field here since it doesn't produce the field on optional values, we filter then use that instead
        let declared_fields = std.array.map (fun kvp => kvp.field) std.record.to_array record in
        std.array.fold_right
          (fun field acc => if (std.record.has_field field record) then acc + 1 else acc)
          0
          fields == 1
    )
  in
let Env = fun label env =>
  env
  |> match {
    { name, value } => env | { name | String, value | String },
    { name, valueFrom } =>
      env.valueFrom
      |> match {
        { resourceFieldRef } =>
          env
            | {
              name | String,
              valueFrom
                | {
                  resourceFieldRef
                    | {
                      containerName | lib.k8s.Name | optional,
                      quantity | String | optional,
                      resource | std.enum.TagOrString | ResourceRefs
                    }
                }
            },
        { secretKeyRef } =>
          env
            | {
              name | String,
              valueFrom
                | {
                  secretKeyRef
                    | {
                      key | String,
                      name | lib.k8s.Name,
                      "optional" | Bool | optional,
                    }
                }
            },
        { configMapKeyRef } =>
          env
            | {
              valueFrom
                | {
                  configMapKeyRef
                    | {
                      key | String,
                      name | lib.k8s.Name,
                      "optional" | Bool | optional,
                    }
                }
            },
        { fieldRef } =>
          env
            | {
              name | String,
              valueFrom
                | {
                  fieldRef | { fieldPath | fieldRefContract, apiVersion | String | optional, }
                }
            },
        _ =>
          std.contract.blame label,
      },
    _ => std.contract.blame label,
  }
in
let EnvFrom = {
  configMapRef | { name | lib.k8s.Name, .. } | optional,
  secretRef | { name | lib.k8s.Name, .. } | optional,
  ..
}
in
let HttpProbeAction = {
  port | lib.k8s.PortOrName, # This technically work but if we write these contracts like this we lose on the big benifit, actually checking if http port is defined? TODO:
  path | String,
  ..
}
in
let Probe = {
  httpGet | { port | lib.k8s.PortOrName, path | String, .. } | optional,
  exec | Array String | optional,
  tcpSocket | { host | String | optional, port | lib.networking.Port } | optional,
  ..
}
in
let Resources = {
  requests | { cpu | lib.k8s.Resource | optional, memory | lib.k8s.Resource | optional, } | optional,
  limits | { cpu | lib.k8s.Resource | optional, memory | lib.k8s.Resource | optional, } | optional,
}
in
# TODO: a lot of these are dependent on pod.spec.os, is this just unset or actually validated and erred --- Need checking
let SecurityContext = {
  allowPrivilegeEscalation | Bool | optional, # not spec.os.name is windows
  capabilities | { add | Array String | optional, drop | Array String | optional, } | optional, # ignore spec.os.windows
  privileged | Bool | optional,
  procMount | String | optional, # not spec.os.name is windows
  readOnlyRootFilesystem | Bool | optional,
  runAsGroup | Number | optional,
  runAsNonRoot | Bool | optional,
  runAsUser | Number | optional,
  seLinuxOptions | { level | String, role | String, type | String, user | String, } | optional, # SELinuxOptions,
  seccompProfile | { localhostProfile | String | optional, type | String } | optional, # SeccompProfile
  windowsOptions | { gmsaCredentialSpec | String, gmsaCredentialSpecName | String, hostProcess | Bool, runAsUserName | String } | optional, # WindowsSecurityContextOptions, # not spec.os.name is linux
  ..
}
in
let ContainerSpec = {
  name | std.string.NonEmpty,
  image | std.string.NonEmpty,
  imagePullPolicy
    | lib.enum.StringOrEnum [| 'Always, 'Never, 'IfNotPresent |]
    | optional,
  ports
    | Array {
      containerPort | lib.networking.Port,
      name | lib.k8s.Name | optional,
      protocol | lib.enum.StringOrEnum [| 'TCP, 'STCP', 'UDP |] | optional,
      ..
    }
    | optional,
  env | Array Env | optional,
  envFrom | Array EnvFrom | optional,
  livenessProbe
    | AllPreds [(OnlyOneOf ["httpGet", "exec", "tcpSocket"])]
    | Probe
    | optional,
  readinessProbe
    | AllPreds [(OnlyOneOf ["httpGet", "exec", "tcpSocket"])]
    | Probe
    | optional,
  startupProbe
    | AllPreds [(OnlyOneOf ["httpGet", "exec", "tcpSocket"])]
    | Probe
    | optional,
  lifecycle # TODO: check these, can lifecycle be something else
    | {
      postStart
        | AllPreds [(OnlyOneOf ["httpGet", "exec"])]
        | {
          httpGet | HttpProbeAction | optional,
          exec | Array String | optional,
        },
      preStop
        | AllPreds [(OnlyOneOf ["httpGet", "exec"])]
        | {
          httpGet | HttpProbeAction | optional,
          exec | Array String | optional,
        }
    }
    | optional,
  resources | Resources | optional,
  securityContext | SecurityContext | optional,
  ..
}
in

let _podAffinityTerm = {
  labelSelector | lib.k8s.LabelSelector | optional,
  namespaceSelecor | lib.k8s.LabelSelector | optional,
  namespaces | Array lib.k8s.Name | optional,
  topologyKey | std.string.NonEmpty,
}
in

let nodeSelectorRequirments =
  # TODO: match me
  let nodeSelectorValidation = fun values label operator =>
    if ((operator == 'In || operator == 'NotIn) && std.array.length values == 0)
    || ((operator == 'Exists || operator == 'DoesNotExist) && std.array.length values != 0)
    || ((operator == 'Gt || operator == 'Lt) && std.array.length values != 1) then
      std.contract.blame_with_message
        m%"operator + values are invalid
          In and NotIn need at least one value
          Exists and DoesNotExist need an empty array
          Gt and Lt need exactly one value"%
        label
    else
      operator
  in
  {
    key | lib.k8s.ValidLabel,
    operator
      | std.enum.TagOrString
      | [| 'In, 'NotIn, 'Exists, 'DoesNotExist, 'Gt, 'Lt |]
      | nodeSelectorValidation values,
    values | Array String,
  }
in
let nodeSelectorTerm = {
  matchExpressions | Array nodeSelectorRequirments | optional,
  matchFields | Array nodeSelectorRequirments | optional,
}
in
let _volumeSource = fun label value =>
  value
  |> match {
    { configMap, name } =>
      value
        | {
          name | lib.k8s.Name,
          configMap | { name | lib.k8s.Name, .. }
        },
    { secret, name } =>
      value
        | {
          name | lib.k8s.Name,
          secret | { secretName | lib.k8s.Name, .. }
        },
    { persistentVolumeClaim, name } =>
      value
        | {
          name | lib.k8s.Name,
          persistentVolumeClaim | { claimName | lib.k8s.Name, .. }
        },
    { emptyDir, name } =>
      value
        | {
          name | lib.k8s.Name,
          emptyDir | { medium | String | optional, sizeLimit | lib.k8s.Resource | optional }
        },
    { projected, name } =>
      value
        | {
          name | lib.k8s.Name,
          projected
            | {
              defaultMode | Number | optional,
              sources
                | Array {
                  configMap
                    | {
                      name | lib.k8s.Name,
                      optional | Bool | optional,
                      items | Array { key | String, mode | Number | optional, path | String, } | optional
                    }
                    | optional,
                  secret
                    | {
                      items | Array { key | String, mode | Number | optional, path | String } | optional,
                      name | String,
                      optional | Bool | optional
                    }
                    | optional
                }
            }
        },
    { hostPath, name } => value | { name | lib.k8s.Name, hostPath | { path | String } },
    _ => std.contract.blame_with_message "Either missing a name for the volume source or you have defined multiple volume sources" label,
  }
in
let _affinity = {
  nodeAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution
        | Array {
          preference | nodeSelectorTerm,
          weight | lib.numbers.InRange 0 100,
        }
        | optional,
      requiredDuringSchedulingIgnoredDuringExecution | { nodeSelectorTerms | Array nodeSelectorTerm | std.array.NonEmpty } | optional,
    }
    | optional,
  podAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution
        | Array { podAffinityTerm | _podAffinityTerm, weight | lib.numbers.InRange 0 100 }
        | optional,
      requiredDuringSchedulingIgnoredDuringExecution | Array _podAffinityTerm | optional,
    }
    | optional,
  podAntiAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution
        | Array { podAffinityTerm | _podAffinityTerm, weight | lib.numbers.InRange 0 100 }
        | optional,
      requiredDuringSchedulingIgnoredDuringExecution | Array _podAffinityTerm | optional,
    }
    | optional,
}
in
# TODO: probably should check the whole record using a pattern match, when { os = "linux" } => and no match is ignored
let onlyLinux
  | doc "predicate to allow certain podspec config to only be available from a specific pod.spec.os.name"
  = fun val => std.contract.from_predicate (fun ignoredRecord => val == null || val.name == 'linux)
  in
let onlyWindows = fun val => std.contract.from_predicate (fun ignoredRecord => val == null || val.name == 'windows) in
let podSpec = {
  activeDeadlineSeconds | std.number.PosNat | optional,
  affinity | _affinity | optional,
  tolerations
    | Array {
      effect | std.enum.TagOrString | [| 'NoSchedule, 'PreferNoSchedule, 'NoExecute |],
      operator | std.enum.TagOrString | [| 'Exists, 'Equal |] | optional,
      ..
    }
    | optional,

  serviceAccountName | lib.k8s.Name | optional,
  # TODO: would this be necessary if we are always converting to a map then back to a list 🤔
  containers | Array ContainerSpec | std.array.NonEmpty, # | lib.arrays.UniqueRecords "name",

  dnsConfig # TODO: figure out what server is validating here
    | {
      nameservers | Array String | optional,
      searches | Array String | optional,
      options | Array { name | String, value | String } | optional,
    }
    | optional,

  dnsPolicy
    | std.enum.TagOrString
    | [| 'ClusterFirstWithHostNet, 'ClusterFirst, 'Default, 'None |]
    | optional,

  hostAliases | Array { hostnames | Array String, ip | String } | optional,
  initContainers | Array ContainerSpec | optional,
  nodeSelector | lib.k8s.Labels | optional, # TODO: basic selector thingy
  restartPolicy | std.enum.TagOrString | [| 'Always, 'OnFailure, 'Never |] | optional,
  os
    | { name | std.enum.TagOrString | [| 'linux, 'windows |], }
    | optional,
  preemptionPolicy | std.enum.TagOrString | [| 'Never, 'PreemptLowerPriority |] | optional,

  securityContext
    | {
      fsGroup | onlyLinux os | Number | optional,
      fsGroupChangePolicy
        | onlyLinux os
        | std.enum.TagOrString
        | [| '"OnRootMismatch", '"Always" |] # not windows check
        | optional,

      runAsGroup
        | onlyLinux os
        | Number
        | optional,

      runAsUser
        | onlyLinux os
        | Number
        | optional,

      seLinuxOptions
        | onlyLinux os
        | {
          level | String | optional,
          role | String | optional,
          type | String | optional,
          user | String | optional,
        }
        | optional,

      seccompProfile
        | onlyLinux os
        | {
          localhostProfile | String | optional,
          type | String
        }
        | optional, # seccompProfile

      windowsOptions
        | onlyWindows os
        | {
          gmsaCredentialSpec | String,
          gmsaCredentialSpecName | String,
          hostProcess | Bool,
          runAsUserName | String
        }
        | optional,
      ..
    }
    | optional,

  subdomain | lib.k8s.Name | optional,
  terminationGracePeriodSeconds | std.number.PosNat | optional,
  topologySpreadConstraints
    | Array {
      maxSkew | std.number.PosNat,
      topologyKey | lib.k8s.ValidLabel,
      labelSelector | lib.k8s.LabelSelector | optional,
      matchLabelKeys | Array lib.k8s.Name | optional,
      nodeAffinityPolicy | std.enum.TagOrString | [| 'Honor, 'Ignore, |] | optional,
      nodeTaintsPolicy | std.enum.TagOrString | [| 'Honor, 'Ignore, |] | optional,
      ..
    }
    | optional,
  volumes | Array { .. } | optional, #_volumeSource | optional, # TODO: what is the best way to model arbitrary sections of volume... Could potentially be generated from schema
  ..
}
in

let job_spec = {
  activeDeadlineSeconds | std.number.PosNat | optional,
  backoffLimit | std.number.PosNat | optional,
  completions | std.number.PosNat | optional,
  completionMode | String | optional, # TODO: enum
  manualSelector | Bool | optional,
  parallelism | std.number.PosNat | optional,
  selector | lib.k8s.LabelSelector | optional,
  suspend | Bool | optional,
  ttlSecondsAfterFinished | std.number.PosNat | optional,
  template
    | {
      metadata | lib.k8s.Metadata | optional,
      spec | podSpec,
    },
  podFailurePolicy
    | {
      rules
        | {
          action | lib.enum.StringOrEnum [| 'FailJob, 'Ignore, 'Count |],
          # TODO: container name here can be null
          # TODO: In can't use 0 in values
          # TODO: MinItems 1 for the number array
          # TODO: At most 255
          onExitCodes
            | { containerName | lib.k8s.Name, operator | lib.enum.StringOrEnum [| 'In, 'NotIn, |], values | Array Number, },
          onPodConditions | Array { status | String | optional, type | String, } | optional,
        }
        | optional,
    }
    | optional,
}
in

{
  apps.v1.Deployment = {
    metadata | lib.k8s.ResourceMetadata,
    apiVersion = "apps/v1",
    kind = "Deployment",
    spec
      | {
        minReadySeconds | std.number.PosNat | optional,
        progressDeadlineSeconds | std.number.PosNat | optional,
        replicas | std.number.PosNat | optional,
        revisionHistoryLimit | std.number.PosNat | optional,
        selector | lib.k8s.WorkloadSelector | SelectorValidatorContract template,
        strategy
          | {
            type | lib.enum.StringOrEnum [| 'RollingUpdate, 'Recreate |] | optional,
            rollingUpdate
              | {
                # This wiill capture strategy, meaning if it is defined it needs a value at least
                maxSurge | deployment_rolling_strategy strategy | lib.numbers.NumberOrPercentage | optional,
                maxUnavailable | deployment_rolling_strategy strategy | std.number.Nat | optional,
              }
              | std.contract.from_predicate (fun val => !(val.maxSurge == 0 && val.maxUnavailable == 0)) # TODO: should these be scoped internally into a predicates record
              | optional
          }
          | optional,
        template
          | {
            metadata | lib.k8s.Metadata,
            spec | podSpec,
          },
        ..
      },
    ..
  },

  apps.v1.StatefulSet = {
    metadata | lib.k8s.ResourceMetadata,
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    spec
      | {
        minReadySeconds | std.number.PosNat | optional,
        ordinals | { start | std.number.PosNat } | optional,
        replicas | std.number.PosNat | optional,
        revisionHistoryLimit | std.number.PosNat | optional,
        podManagementPolicy | lib.enum.StringOrEnum [| 'Parallel, 'OrderedReady |] | optional,
        selector | lib.k8s.WorkloadSelector | SelectorValidatorContract template,
        serviceName | lib.k8s.Name,
        template = {
          metadata | lib.k8s.Metadata,
          spec | podSpec,
        },
        persistentVolumeClaimRetentionPolicy
          | {
            whenDeleted | lib.enum.StringOrEnum [| 'Delete, 'Retain |] | optional,
            whenScaled | lib.enum.StringOrEnum [| 'Delete, 'Retain |] | optional,
          }
          | optional,
        updateStrategy
          | {
            type | lib.enum.StringOrEnum [| 'RollingUpdate, 'OnDelete |] | optional,
            rollingUpdate # TODO: Lock this similar to deployment spec
              | {
                partition | std.number.Nat | optional,
                maxUnavailable | lib.numbers.NumberOrPercentage | optional
              }
              | optional,
          }
          | optional,
        # volumeClaimTemplates | Array { .. } | optional, # TODO: model me with pvc template
        ..
      },
    ..
  },

  v1.Pod = {
    metadata | lib.k8s.ResourceMetadata,
    apiVersion = "v1",
    kind = "Pod",
    spec | podSpec,
    ..
  },

  batch.v1.CronJob = {
    metadata | lib.k8s.ResourceMetadata,
    apiVersion = "batch/v1",
    kind = "CronJob",
    spec
      | {
        failedJobsHistoryLimit | std.number.PosNat | optional,
        schedule | String, # TODO: validation,
        startingDeadline | std.number.PosNat | optional,
        successfulJobsHistoryLimit | std.number.PosNat | optional,
        timeZone | String | optional, # timezone contract later
        jobTemplate | { metadata | lib.k8s.Metadata | optional, spec | job_spec },
      },
    ..
  },

  batch.v1.Job = {
    apiVersion = "batch/v1",
    kind = "Job",
    metadata | lib.k8s.ResourceMetadata,
    spec
      | {
        activeDeadlineSeconds | std.number.PosNat | optional,
        backoffLimit | std.number.PosNat | optional,
        completions | std.number.PosNat | optional,
        completionMode | String | optional, # TODO: enum
        manualSelector | Bool | optional,
        parallelism | std.number.PosNat | optional,
        selector | lib.k8s.LabelSelector | optional,
        ttlSecondsAfterFinished | std.number.PosNat | optional,
        template
          | {
            metadata | lib.k8s.Metadata | optional,
            spec | podSpec,
          },
        podFailurePolicy
          | {
            rules
              | {
                action | lib.enum.StringOrEnum [| 'FailJob, 'Ignore, 'Count |],
                # TODO: container name here can be null
                # TODO: In can't use 0 in values
                # TODO: MinItems 1 for the number array
                # TODO: At most 255
                onExitCodes
                  | { containerName | lib.k8s.Name, operator | lib.enum.StringOrEnum [| 'In, 'NotIn, |], values | Array Number, },
                onPodConditions | Array { status | String | optional, type | String, } | optional,
              }
              | optional,
          }
          | optional,
      },
    ..
  },

  apps.v1.DaemonSet = {
    apiVersion = "apps/v1",
    kind = "DaemonSet",
    metadata | lib.k8s.ResourceMetadata,
    spec
      | {
        selector | lib.k8s.WorkloadSelector | SelectorValidatorContract template,
        updateStrategy | { .. } | optional,
        template | { spec | podSpec, metadata | lib.k8s.Metadata | optional },
      },
    ..
  },
}
