let lib = import "lib.ncl" in
let ContainerPort = {
  containerPort | lib.networking.Port,
  name | lib.k8s.Name | optional,
  protocol | lib.enum.StringOrEnum [| 'TCP, 'STCP', 'UDP |] | optional,
  ..
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
  std.contract.from_predicate
    (fun record => std.array.fold_right (fun pred acc => pred record && acc) true preds)
in
let Required
  | doc "ensure a record has the set of properties, useful when used with OneOf or when the record has unknown fields but need to enforce check on known fields"
  = fun fields =>
    (
      fun record => (std.array.fold_right (fun field acc => if !std.record.has_field (field) record then false else acc) true fields)
    )
  in
let OnlyOneOf # this will be higher order func called on the reocrd
  | doc "simple XOR implementation for fields at the same root level"
  = fun fields =>
    (
      fun record =>
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
let ExecAction | doc "Array of commands to execute" = Array String in
let TcpSocketAction = { host | String | optional, port | lib.networking.Port } in
let Probe = {
  httpGet | HttpProbeAction | optional,
  exec | Array String | optional,
  tcpSocket | TcpSocketAction | optional,
  ..
}
in
let KubeResource =
  std.contract.from_predicate
    (fun val => std.is_number val || std.string.is_match "^[0-9]+(\\.[0-9]+)?(mi?|k|Ki|Mi?|Gi?|Ti?|Pi?|Ei?)?$" val)
in
let AResource = {
  cpu | KubeResource | optional,
  memory | KubeResource | optional,
}
in
let Resources = {
  requests | AResource | optional,
  limits | AResource | optional,
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
{
  ContainerSpec = {
    name | String | std.string.NonEmpty,
    image | String,
    imagePullPolicy
      | lib.enum.StringOrEnum [| 'Always, 'Never, 'IfNotPresent |]
      | optional,
    ports | Array ContainerPort | optional,
    env | Array Env | optional,
    envFrom | Array  EnvFrom | optional,
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
  },
}
