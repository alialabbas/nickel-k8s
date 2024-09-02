let { Env, .. } = import "../kube.ncl" in
{
  # any deployment defined in this env would have a default replica of 20
  Overlays = {
    Deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      spec = {
        replicas | force = 20,
      },
    },
  },
  # Ensures all deployment define in this env have at least a replica of 10
  # TODO: this is not working now for whatever reason
  Constraints = {
    Deployment = {
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
  },
  Releases =
    {
      opentelemetry-collector = (import "otel.ncl"),
    }
    # This is explicitly loaded here to ensure we have the correct computation of variables all the time
    & (import "./versions.ncl")
}
  | Env
