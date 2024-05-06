let { Numbers, Arrays, Strings, Records, .. } = import "types.ncl" in
let { Kube, .. } = import "kube.ncl" in
let { ContainerSpec, .. } = import "containerSpec.ncl" in
let { Metadata, LabelSelector, ValidLabel, Labels, .. } = import "metadata.ncl" in

let _podAffinityTerm = {
  labelSelector | LabelSelector | optional,
  namespaceSelecor | LabelSelector | optional,
  namespaces | Array Kube.Name | optional,
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
    key | ValidLabel,
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
          name | Kube.Name,
          configMap | { name | Kube.Name, .. }
        },
    { secret, name } =>
      value
        | {
          name | Kube.Name,
          secret | { secretName | Kube.Name, .. }
        },
    { persistentVolumeClaim, name } =>
      value
        | {
          name | Kube.Name,
          persistentVolumeClaim | { claimName | Kube.Name, .. }
        },
    { emptyDir, name } =>
      value
        | {
          name | Kube.Name,
          emptyDir | { medium | String | optional, sizeLimit | Kube.Resource | optional }
        },
    { projected, name } =>
      value
        | {
          name | Kube.Name,
          projected
            | {
              defaultMode | Number | optional,
              sources
                | Array {
                  configMap
                    | {
                      name | Kube.Name,
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
    { hostPath, name } => value | { name | Kube.Name, hostPath | { path | String } },
    _ => std.contract.blame_with_message "Either missing a name for the volume source or you have defined multiple volume sources" label,
  }
in
let _affinity = {
  nodeAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution
        | Array {
          preference | nodeSelectorTerm,
          weight | Numbers.InRange 0 100,
        }
        | optional,
      requiredDuringSchedulingIgnoredDuringExecution | { nodeSelectorTerms | Array nodeSelectorTerm | Arrays.MinItems 1 } | optional,
    }
    | optional,
  podAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution | Array { podAffinityTerm | _podAffinityTerm, weight | Numbers.InRange 0 100 } | optional,
      requiredDuringSchedulingIgnoredDuringExecution | Array _podAffinityTerm | optional,
    }
    | optional,
  podAntiAffinity
    | {
      preferredDuringSchedulingIgnoredDuringExecution | Array { podAffinityTerm | _podAffinityTerm, weight | Numbers.InRange 0 100 } | optional,
      requiredDuringSchedulingIgnoredDuringExecution | Array _podAffinityTerm | optional,
    }
    | optional,
}
in
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
      key | String | optional,
      operator | std.enum.TagOrString | [| 'Exists, 'Equal |] | optional,
      tolerationSeconds | Number | optional,
      value | String | optional,
    }
    | optional,

  automountServiceAccountToken | Bool | optional,
  serviceAccountName | Kube.Name | optional,
  containers | Array ContainerSpec | Arrays.MinItems 1 | Arrays.UniqueRecords "name",

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

  enableServiceLinks | Bool | optional,
  hostAliases | Array { hostnames | Array String, ip | String } | optional,
  hostIPC | Bool | optional,
  hostNetwork | Bool | optional,
  hostPID | Bool | optional,
  hostUsers | Bool | optional,
  hostname | String | optional,
  imagePullSecrets | Array { name | String } | optional,
  initContainers | Array ContainerSpec | optional,
  nodeName | String | optional,
  nodeSelector | Labels | optional, # TODO: basic selector thingy
  restartPolicy | std.enum.TagOrString | [| 'Always, 'OnFailure, 'Never |] | optional,
  os
    | doc m%%"Due to technical reason, this contract is forcing all specs to have a null value when evaluated.
This emulate what typically done by the server and the security checks will only happen when spec.os.name is specified.
  "%%
    | Records.Nullable { name | std.enum.TagOrString | [| 'linux, 'windows |], }
    | optional
    | default
    = null,
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

      runAsNonRoot
        | Bool
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
    }
    | optional,

  readinessGates | Array { conditionType | String } | optional,
  runtimeClassName | String | optional,
  schedulerName | String | optional,
  schedulingGates | Array { name | String } | optional,
  setHostnameAsFQDN | Bool | optional,
  shareProcessNamespace | Bool | optional,
  subdomain | Kube.Name | optional,
  terminationGracePeriodSeconds | std.number.PosNat | optional,
  topologySpreadConstraints
    | Array {
      maxSkew | std.number.PosNat,
      topologyKey | ValidLabel,
      whenUnsatisfiable | String,
      labelSelector | LabelSelector | optional,
      matchLabelKeys | Array Kube.Name | optional,
      minDomains | Number | optional,
      nodeAffinityPolicy | std.enum.TagOrString | [| 'Honor, 'Ignore, |] | optional,
      nodeTaintsPolicy | std.enum.TagOrString | [| 'Honor, 'Ignore, |] | optional,
    }
    | optional,
  volumes | Array _volumeSource | optional,
}
in
{
  Pod = {
    metadata | Metadata,
    apiVersion = "v1",
    kind = "pod",
    spec | PodSpec
  },
  PodSpec = podSpec,
}
