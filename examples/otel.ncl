let { Release, .. } = import "../kube.ncl" in
let { ValidateServiceMatchPod, PortCheck, .. } = import "../release-validations.ncl" in

let baseName = "opentelemetry-collector" in
let appName : String -> String
  = fun releaseName =>
    if releaseName != "" && releaseName != baseName then
      releaseName ++ "-" ++ baseName
    else
      baseName
  in

let commonLabels : String -> String -> { _ : String }
  = fun releaseName version =>
    let baseLabels = {
      "app.kubernetes.io/name" = baseName,
      "app.kubernetes.io/version" = version,
    }
    in
    if releaseName != "" then
      baseLabels
      & {
        "app.kubernetes.io/instance" = releaseName,
      } | { _ : String }
    else
      baseLabels | { _ : String }
  in

let otelConfig = import "./config.yaml" in

{
  Inputs | not_exported
    = {
      version | String | default = "0.0.97",
      namespace | String | default = "monitoring",
      releaseName | doc "release name controls metadata.name across all manifest" | String | default = "opentelemetry-collector",
    },
  Manifests = {
    serviceAccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        labels = commonLabels Inputs.releaseName Inputs.version,
        name = appName Inputs.releaseName,
        namespace = Inputs.namespace,
      },
    },
    configMap = {
      apiVersion = "v1",
      kind = "ConfigMap",
      data = {
        relay =
          std.serialize
            'Yaml
            (
              (import "./config.yaml") | (import "./otelconfig.ncl")
            ),
      },
      metadata = {
        labels = commonLabels Inputs.releaseName Inputs.version,
        name = appName Inputs.releaseName,
        namespace = Inputs.namespace,
      },
    },
    service =
      {
        apiVersion | force = "v1",
        kind = "Service",
        metadata = {
          labels = commonLabels Inputs.releaseName Inputs.version,
          name = appName Inputs.releaseName,
          namespace = Inputs.namespace,
        },
        spec = {
          internalTrafficPolicy = "Cluster",
          ports = [
            {
              name = "jaeger-compact",
              port = 6831,
              protocol = "UDP",
              targetPort = 6831,
            },
            {
              name = "jaeger-grpc",
              port = 14250,
              protocol = "TCP",
              targetPort = 14250,
            },
            {
              name = "jaeger-thrift",
              port = 14268,
              protocol = "TCP",
              targetPort = 14268,
            },
            {
              appProtocol = "grpc",
              name = "otlp",
              port = 4317,
              protocol = "TCP",
              targetPort = 4317,
            },
            {
              name = "otlp-http",
              port = 4319,
              protocol = "TCP",
              targetPort = 4318,
            },
            {
              name = "zipkin",
              port = 9411,
              protocol = "TCP",
              targetPort = 9411,
            },
          ],
          selector = commonLabels Inputs.releaseName Inputs.version,
          type = "ClusterIP",
        },
      } | ValidateServiceMatchPod deployment.spec.template | PortCheck deployment.spec.template.spec,
    deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = commonLabels Inputs.releaseName Inputs.version,
        name = appName Inputs.releaseName,
        namespace = Inputs.namespace,
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = commonLabels Inputs.releaseName Inputs.version,
          # TODO: nothing in kube really check the correctness of these expressions.
          # Logical testing should maybe out of concern here
          matchExpressions = [
            {
              key = "app.kubernetes.io/namesss",
              operator = "DoesNotExist"
            },
            {
              key = "app.kubernetes.io/name",
              operator = "Exists",
            },
            {
              key = "app.kubernetes.io/version",
              operator = "In",
              values = [Inputs.version, "invalid"]
            },
            {
              key = "app.kubernetes.io/version",
              operator = "NotIn",
              values = ["invalid"],
            },
          ]
        },
        strategy = { type = "RollingUpdate", rollingUpdate.maxSurge = 10, rollingUpdate.maxUnavailable = 50 },
        template = {
          metadata = {
            labels = commonLabels Inputs.releaseName Inputs.version,
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
                  },
                  { name = "overlayed-env", value = "overridden" },
                ],
                image = "otel/opentelemetry-collector-contrib:" ++ Inputs.version,
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
                livenessProbe = { httpGet = { path = otelConfig.extensions.health_check.path, port = 13133, }, },
                readinessProbe = livenessProbe,
                securityContext = {},
                volumeMounts = [
                  {
                    mountPath = "/conf",
                    # TODO: this is a domain logic that I don't think it is possible to capture in a generic test approach
                    # Only way is to really just separate how these stuff work
                    name = appName Inputs.releaseName,
                  }
                ],
              }
            ],
            hostNetwork = false,
            securityContext = {},
            serviceAccountName = appName Inputs.releaseName,
            volumes = [
              {
                configMap = {
                  items = [
                    {
                      key = "relay",
                      path = "relay.yaml",
                    },
                  ],
                  name = appName Inputs.releaseName,
                },
                name = appName Inputs.releaseName,
              }
            ],
          },
        },
      },
    },
  },
  Overlays = [
    {
      apiVersion = "apps/v1",
      kind = "Deployment",
      spec = {
        replicas | force = 20,
        template.spec.containers = [
          {
            name = "opentelemetry-collector",
            env = [
              {
                name = "overlayed-env",
                value | force = "test-val",
              }
            ],
          },
        ]
      },
    },
  ]
} | Release
