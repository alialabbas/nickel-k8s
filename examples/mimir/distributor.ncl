{
    distributor-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        annotations = {},
        labels = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/part-of" = "memberlist",
          "app.kubernetes.io/version" = "2.12.0",
          "helm.sh/chart" = "mimir-distributed-5.3.0",
        },
        name = "mimir-distributed-distributor",
        namespace = "default",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "distributor",
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/name" = "mimir",
          },
        },
        strategy = {
          rollingUpdate = { maxSurge = "15%", maxUnavailable = 0, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            annotations = {
              "checksum/config" = "f6adb4c80ecb4ccb1ddf90f3364c08b86205936a6de06f43e0f3216ced2a89e3",
            },
            labels = {
              "app.kubernetes.io/component" = "distributor",
              "app.kubernetes.io/instance" = "mimir-distributed",
              "app.kubernetes.io/managed-by" = "Helm",
              "app.kubernetes.io/name" = "mimir",
              "app.kubernetes.io/part-of" = "memberlist",
              "app.kubernetes.io/version" = "2.12.0",
              "helm.sh/chart" = "mimir-distributed-5.3.0",
            },
            namespace = "default",
          },
          spec = {
            containers = [
              {
                args = [
                  "-target=distributor",
                  "-config.expand-env=true",
                  "-config.file=/etc/mimir/mimir.yaml",
                  "-server.grpc.keepalive.max-connection-age=60s",
                  "-server.grpc.keepalive.max-connection-age-grace=5m",
                  "-server.grpc.keepalive.max-connection-idle=1m",
                  "-shutdown-delay=90s"
                ],
                env = [
                  {
                    name = "GOMAXPROCS",
                    value = "8",
                  },
                  {
                    name = "JAEGER_REPORTER_MAX_QUEUE_SIZE",
                    value = "1000",
                  }
                ],
                image = "grafana/mimir:2.12.0",
                imagePullPolicy = "IfNotPresent",
                name = "distributor",
                ports = [
                  {
                    containerPort = 8080,
                    name = "http-metrics",
                    protocol = "TCP",
                  },
                  {
                    containerPort = 9095,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = 7946,
                    name = "memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = {
                    path = "/ready",
                    port = "http-metrics",
                  },
                  initialDelaySeconds = 45,
                },
                resources = {
                  requests = {
                    cpu = "100m",
                    memory = "512Mi",
                  },
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    mountPath = "/data",
                    name = "storage",
                  },
                  {
                    mountPath = "/active-query-tracker",
                    name = "active-queries",
                  }
                ],
              }
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
              seccompProfile = { type = "RuntimeDefault", },
            },
            serviceAccountName = "mimir-distributed",
            terminationGracePeriodSeconds = 100,
            topologySpreadConstraints = [
              {
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/component" = "distributor",
                    "app.kubernetes.io/instance" = "mimir-distributed",
                    "app.kubernetes.io/name" = "mimir",
                  },
                },
                maxSkew = 1,
                topologyKey = "kubernetes.io/hostname",
                whenUnsatisfiable = "ScheduleAnyway",
              }
            ],
            volumes = [
              {
                configMap = {
                  items = [
                    {
                      key = "mimir.yaml",
                      path = "mimir.yaml",
                    }
                  ],
                  name = "mimir-distributed-config",
                },
                name = "config",
              },
              {
                configMap = {
                  name = "mimir-distributed-runtime",
                },
                name = "runtime-config",
              },
              { emptyDir = {}, name = "storage", },
              {
                emptyDir = {},
                name = "active-queries",
              }
            ],
          },
        },
      },
    },
    distributor-headless-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        annotations = {},
        labels = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/part-of" = "memberlist",
          "app.kubernetes.io/version" = "2.12.0",
          "helm.sh/chart" = "mimir-distributed-5.3.0",
          "prometheus.io/service-monitor" = "false",
        },
        name = "mimir-distributed-distributor-headless",
        namespace = "default",
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            name = "http-metrics",
            port = 8080,
            protocol = "TCP",
            targetPort = "http-metrics",
          },
          {
            name = "grpc",
            port = 9095,
            protocol = "TCP",
            targetPort = "grpc",
          }
        ],
        selector = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
        },
        type = "ClusterIP",
      },
    },
    distributor-poddisruptionbudget = {
      apiVersion = "policy/v1",
      kind = "PodDisruptionBudget",
      metadata = {
        labels = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/version" = "2.12.0",
          "helm.sh/chart" = "mimir-distributed-5.3.0",
        },
        name = "mimir-distributed-distributor",
        namespace = "default",
      },
      spec = {
        maxUnavailable = 1,
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "distributor",
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/name" = "mimir",
          },
        },
      },
    },
    distributor-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        annotations = {},
        labels = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/part-of" = "memberlist",
          "app.kubernetes.io/version" = "2.12.0",
          "helm.sh/chart" = "mimir-distributed-5.3.0",
        },
        name = "mimir-distributed-distributor",
        namespace = "default",
      },
      spec = {
        ports = [
          {
            name = "http-metrics",
            port = 8080,
            protocol = "TCP",
            targetPort = "http-metrics",
          },
          {
            name = "grpc",
            port = 9095,
            protocol = "TCP",
            targetPort = "grpc",
          }
        ],
        selector = {
          "app.kubernetes.io/component" = "distributor",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
        },
        type = "ClusterIP",
      },
    },
    }
