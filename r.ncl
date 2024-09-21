let { apps, .. } = import "deployment.ncl" in
# Testability of these contracts sucks
# I can't break laziness unless I evaluate it
# And then I can't figure out if it failed.
# optional 1: break the contracts to be Json Based implementation. This will work but it introduce so much work to shuffle back to contract once there is a support for it
# non-lazy... I am banking on these to make sure what i have is correct.
# another option is to test this with some sort of integration test to
{
  apiVersion = "apps/v1",
  kind = "Deployment",
  metadata = {
    name = "otel"
  },
  spec = {
    replicas = 1,
    revisionHistoryLimit = 10,
    strategy = { type = "RollingUpdate", rollingUpdate.maxSurge = 10, rollingUpdate.maxUnavailable = 50 },
    selector = {
      matchLabels = {
        "apps.kubernetes.io/name" = "opentelemetry-collector"
      },
    },
    template = {
      metadata = {
        labels = { "apps.kubernetes.io/name" = "opentelemetry-collector" },
      },
      spec = {
        containers = [
          {
            command = [
              "/otelcol-contrib",
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
              }
            ],
            image = "otel/opentelemetry-collector-contrib:",
            imagePullPolicy = "IfNotPresent",
            name = "opentelemetry-collector",
            ports = [
              {
                containerPort = 6831,
                name = "jaeger-compact",
                protocol = "UDP",
              },
              {
                containerPort = 14250,
                name = "jaeger-grpc",
                protocol = "TCP",
              },
              {
                containerPort = 14268,
                name = "jaeger-thrift",
                protocol = "TCP",
              },
              {
                containerPort = 4317,
                name = "otlp",
                protocol = "TCP",
              },
              {
                containerPort = 4318,
                name = "otlp-http",
                protocol = "TCP",
              },
              {
                containerPort = 9411,
                name = "zipkin",
                protocol = "TCP",
              }
            ],
            securityContext = {},
          }
        ],
      },
    },
  },
} | std.contract.check apps.v1.Deployment
