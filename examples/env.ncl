let k = import "../kube.ncl" in
let p = import "../policies.ncl" in
let env =
  {
    overlays = [
      # Based on the policies defined in this environment, such an override or a source would not be deployed
      # {
      #   apiVersion = "apps/v1",
      #   kind = "Deployment",
      #   metadata.name = "opentelemetry-collector",
      #   spec.template.spec.containers = [
      #     {
      #       name = "opentelemetry-collector",
      #       image = "imaginary-registry/otel/collector:0.121.0"
      #     }
      #   ],
      # },
    ],

    env_metadata = {
      namespace = "monitoring",
      # prefix = "lgtm-",
      labels = {
        "myorg.myteam/env" = "prod",
      }
    },

    constraints = [
      p.Deployment.ResourceRequestsIsSet,
      p.Deployment.ImageAllowed ["docker.io", "ghcr.io", "quay.io"],
    ],

    releases =
      {
        namespaces = {
          release_metadata.prefix | force = "",
          manifests = { monitoring = { kind = "Namespace", metadata.name = "monitoring", apiVersion = "v1" } }
        },
        crds = import "../crds.ncl",
        minio = import "minio.ncl",
        loki = import "loki.ncl",
        grafana = import "grafana.ncl",
        mimir = import "mimir.ncl",
        tempo = import "tempo.ncl",
        pyroscope = import "pyroscope.ncl",
        opentelemetry-collector = import "otel.ncl",
      }
      & (import "./versions.ncl"),

    k8s_schema = import "./k8s-v1.31.0-swagger.json",
    # crds = (import "./stripped-down-crds.yaml"),
  }
    | k.Env
in
k.build env
