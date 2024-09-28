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
  Releases =
    {
      opentelemetry-collector =
        (import "otel.ncl")
        & {
          Constraints = [
            p.Deployment.ImageAllowed ["test"],
            p.Deployment.RequestResourceSet,
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
                    },
                  },
                ]
              }
            },
          ]
        },
      namespaces =
        {
          Manifests = {
            monitoring = {
              apiVersion = "v1",
              kind = "Namespace",
              metadata.name = "monitoring"
            },
          },
        } | k.Release,
    }
    # This is explicitly loaded here to ensure we have the correct computation of variables all the time
    & (import "./versions.ncl")
}
  | k.Env
