# Utilities to generate a common set of dependent resources
# e.g. from a deployment/statefulset/daemonset, generate a mapping service
# from service get an ingress object
# from service get prometheus servicemonitor and so on
let all = import "all.ncl" in

let fromContainerPortToServicePort = fun p =>
  {
    name = p.name,
    port = p.containerPort,
    protocol = p.protocol,
  }
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
            |> std.array.map
              (
                fun e =>
                  e.ports
                  |> std.array.map
                    (
                      fun p => fromContainerPortToServicePort p
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
      svc
      & {
        spec = { clusterIP = "None" },
        metadata.name = svc.metadata.name ++ "-headless",
      },
  # This one is somewhat useless in a world of easy self referential and strong types
  VolumeFromConfigMap
    | doc "Genarate a ConfigMap volume and VolumeMount for a ConfigMap"
    | all.v1.ConfigMap -> Dyn
    = fun value =>
      {
        volumes = []
      },
}
