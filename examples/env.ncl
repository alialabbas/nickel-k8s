let k = import "../kube.ncl" in
let p = import "../policies.ncl" in
{
  # any deployment defined in this env would have a default replica of 20
  Overlays = [
    {
      apiVersion = "apps/v1",
      kind = "Deployment",
      spec = {
        replicas | force = 20,
      },
    },
  ],
  # Ensures all deployment define in this env have at least a replica of 10
  # TODO: this is not working now for whatever reason
  Constraints = [
    {
      apiVersion = "apps/v1",
      kind = "Deployment",
      spec
        | {
          replicas | Number | std.contract.from_predicate (fun val => val >= 10),
          ..
        }
        | optional,
      ..
    }
  ],
  ReleaseInputs = {
    namespace = "not-used", # this is not overriden because the release namespace is set for otel package
    labels = {
      "myorg.myteam/env" = "prod",
    }
  },
  Releases =
    {
      # with name prefixing, this gets interesting.
      # this inputs stuff should be after the overlays but before constraints
      # constraints are generic so it would make sense to check for certain thing based on the label
      opentelemetry-collector =
        (import "otel.ncl")
        & {
          Constraints = [
            p.Deployment.ImageAllowed ["test"],
            p.Deployment.ResourceRequestsIsSet,
            p.Deployment.ResourceLimitIsSet
          ],
          Overlays = [
            {
              apiVersion = "apps/v1",
              kind = "Deployment",
              metadata = { name = "opentelemetry-collector" },
              spec = {
                template.spec.containers = [
                  {
                    name = "opentelemetry-collector",
                    image = "test:1.1.0",
                    resources = {
                      requests = {
                        cpu = "1",
                        memory = "10Gi",
                      },
                      limits = {
                        cpu = "1",
                        memory = "20Gi",
                      },
                    },
                  },
                ]
              }
            },
          ]
        },
      namespaces =
        {
          # TODO: This still leaks left over values due to merging behaviors
          Inputs = {} | {},
          Manifests = {
            monitoring = {
              apiVersion = "v1",
              kind = "Namespace",
              metadata.name = "monitoring"
            },
          },
        } | k.Release {},
    }
    # This is explicitly loaded here to ensure we have the correct computation of variables all the time
    & (import "./versions.ncl"),

  k8s_schema = import "./k8s-v1.31.0-swagger.json",
  crds = import "./stripped-down-crds.yaml",
}
  | k.Env
