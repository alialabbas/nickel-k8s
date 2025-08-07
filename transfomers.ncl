# Utilities to generate a common set of dependent resources
# e.g. from a deployment/statefulset/daemonset, generate a mapping service
# from service get an ingress object
# from service get prometheus servicemonitor and so on
let all = import "all.ncl" in

let fromContainerPortToServicePort = fun p =>
  {
    name = p.name,
    port = p.containerPort,
  }
  & (if std.record.has_field "protocol" p then { protocol = p.protocol } else {})
in
{
  ServiceFromDeployment
    | doc "Create a ClusterIP service from the given deployment"
    | all.apps.v1.Deployment -> all.v1.Service
    = fun value =>
      {
        metadata = value.metadata,
        spec = {
          type = "ClusterIP",
          ports =
            value.spec.template.spec.containers
            |> std.array.map (fun e =>
              std.record.get_or "ports" [] e
              |> std.array.map (fun p => fromContainerPortToServicePort p
              )
            )
            |> std.array.flatten,
          selector = value.spec.selector.matchLabels,
        }
      },
  HeadlessServiceForWorkload
    | doc "Create a headless service matchings the pod template in the worload spec"
    | all.apps.v1.Deployment -> all.v1.Service
    = fun value =>
      let svc = ServiceFromDeployment value in
      let metadata = svc.metadata |> std.record.update "name" (svc.metadata.name ++ "-headless") in
      # we don't want to introduce any merge priority in here to allow us to avoid recursive conflict in our merge system
      svc
      & {
        spec = { clusterIP = "None", publishNotReadyAddresses = true },
      } |> std.record.update "metadata" metadata,
  PodDisruptionBudgetForWorkload
    | doc "Create a disruption budget matching any k8s workload"
    | { _ | Dyn } -> [| 'maxUnavailable Number, 'minAvailable Number |] -> Dyn
    = fun workload configuration =>
      {
        apiVersion = "policy/v1",
        kind = "PodDisruptionBudget",
        metadata = workload.metadata,
        spec =
          {
            selector = workload.spec.selector,
          }
          & (
            configuration
            |> match {
              'maxUnavailable v => { maxUnavailable = v },
              'minAvailable v => { minAvailable = v },
            }
          ),
      },

  VolumeFromConfigMap
    | doc "Genarate a ConfigMap volume and VolumeMount for a ConfigMap"
    | all.v1.ConfigMap -> Dyn
    = fun value =>
      let keys = std.record.get_or "data" {} value |> std.record.fields in
      {
        name = value.metadata.name,
        configMap = {
          name = value.metadata.name,
          items = std.array.fold_right (fun e acc => acc @ [{ key = e, path = e }]) [] keys,
        },
      },
}
