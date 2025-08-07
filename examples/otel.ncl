let { Release, .. } = import "../kube.ncl" in
let s = import "../nickel-schema.ncl" in
let k8s = import "./k8s-v1.31.0-swagger.json" in
let k8s = s.k8s_schemas k8s in
let { ValidateServiceMatchPod, PortCheck, .. } = import "../release-validations.ncl" in
let t = import "../transfomers.ncl" in

let otelConfig = import "./config.yaml" in
let getReceiverPort : String -> Number = fun r =>
  let parts = std.string.split ":" r in
  std.array.last parts |> std.string.to_number
in

# Defining the schema, then passing it and having to define its input again kind doesn't make sense
let InputSchema = {
  version | String | default = "0.124.0",
  config
    | (import "otelconfig.ncl")
    # | default # To default or not to default?
    = import "config.yaml",
}
in
{
  inputs | InputSchema = {},
  manifests = {
    serviceAccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        labels = {
          "app.kubernetes.io/name" = name,
          "app.kubernetes.io/version" = inputs.version,
        },
        name = "opentelemetry-collector",
      },
    },
    configMap = {
      apiVersion = "v1",
      kind = "ConfigMap",
      data = {
        relay =
          std.serialize
            'Yaml
            inputs.config,
      },
      metadata = {
        labels = serviceAccount.metadata.labels,
        name = serviceAccount.metadata.name,
      },
    },
    service = t.ServiceFromDeployment deployment,
    deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = serviceAccount.metadata.labels,
        name = serviceAccount.metadata.name,
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = serviceAccount.metadata.labels,
        },
        strategy = { type = "RollingUpdate", rollingUpdate.maxSurge = 10, rollingUpdate.maxUnavailable = 50 },
        template = {
          metadata = {
            labels = deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                command = [
                  "/otelcol-k8s",
                  "--config=/conf/relay.yaml"
                ],
                env = [
                  {
                    name = "MY_POD_IP",
                    valueFrom = {
                      fieldRef = {
                        apiVersion = "v1",
                        fieldPath = "status.podIP",
                      },
                    },
                  },
                  { name = "overlayed-env", value = "overridden" },
                ],
                image | default = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s:" ++ inputs.version,
                imagePullPolicy = "IfNotPresent",
                name = "opentelemetry-collector",
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                ports = [
                  {
                    containerPort = getReceiverPort otelConfig.receivers.jaeger.protocols.thrift_compact.endpoint,
                    name = "jaeger-compact",
                    protocol = "UDP",
                  },
                  {
                    containerPort = getReceiverPort otelConfig.receivers.jaeger.protocols.grpc.endpoint,
                    name = "jaeger-grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = getReceiverPort otelConfig.receivers.jaeger.protocols.thrift_http.endpoint,
                    name = "jaeger-thrift",
                    protocol = "TCP",
                  },
                  {
                    containerPort = getReceiverPort otelConfig.receivers.otlp.protocols.grpc.endpoint,
                    name = "otlp",
                    protocol = "TCP",
                  },
                  {
                    containerPort = getReceiverPort otelConfig.receivers.otlp.protocols.http.endpoint,
                    name = "otlp-http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = getReceiverPort otelConfig.receivers.zipkin.endpoint,
                    name = "zipkin",
                    protocol = "TCP",
                  }
                ],
                livenessProbe = {
                  httpGet = {
                    path = otelConfig.extensions.health_check.path,
                    port = getReceiverPort otelConfig.extensions.health_check.endpoint,
                  },
                },
                readinessProbe = livenessProbe,
                securityContext = {},
                volumeMounts = [
                  {
                    mountPath = "/conf",
                    name = serviceAccount.metadata.name,
                  }
                ],
              }
            ],
            hostNetwork = false,
            securityContext = {},
            serviceAccountName = serviceAccount.metadata.name,
            volumes = [
              {
                configMap = {
                  items = [
                    {
                      key = "relay",
                      path = "relay.yaml",
                    },
                  ],
                  name = serviceAccount.metadata.name,
                },
                name = serviceAccount.metadata.name,
              }
            ],
          },
        },
      },
    },
    svcMonitor = {
      apiVersion = "monitoring.coreos.com/v1",
      kind = "ServiceMonitor",
      metadata = {
        labels = { serviceMonitorSelector = "prometheus", },
        name = "prometheus",
      },
      spec = {
        endpoints = [{ interval = "30s", path = "/metrics", targetPort = 9090, }],
        namespaceSelector = { matchNames = ["prometheus"], },
        selector = { matchLabels = { operated-prometheus = "true", }, },
      },
    }
  },
} | Release
