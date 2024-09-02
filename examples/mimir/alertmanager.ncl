{
  alertmanager-config = {
    apiVersion = "v1",
    data = {
      "alertmanager_fallback_config.yaml" = (std.serialize 'Yaml (import "alertmanager-config.yaml"))
    },
    kind = "ConfigMap",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
      },
      name = "mimir-distributed-alertmanager-fallback-config",
      namespace = "default",
    },
  },
  alertmanager-headless = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        "prometheus.io/service-monitor" = "false",
      },
      name = "mimir-distributed-alertmanager-headless",
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
        },
        { name = "cluster", port = 9094, protocol = "TCP", }
      ],
      publishNotReadyAddresses = true,
      selector = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
      },
      type = "ClusterIP",
    },
  },
  alertmanager-pdb = {
    apiVersion = "policy/v1",
    kind = "PodDisruptionBudget",
    metadata = {
      labels = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
      },
      name = "mimir-distributed-alertmanager",
      namespace = "default",
    },
    spec = {
      maxUnavailable = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "alertmanager",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
        },
      },
    },
  },
  alertmanager-service = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
      },
      name = "mimir-distributed-alertmanager",
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
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
      },
      type = "ClusterIP",
    },
  },
  alertmanager-statefulset = {
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "alertmanager",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
      },
      name = "mimir-distributed-alertmanager",
      namespace = "default",
    },
    spec = {
      replicas = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "alertmanager",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
        },
      },
      serviceName = "mimir-distributed-alertmanager",
      template = {
        metadata = {
          annotations = {
            "checksum/alertmanager-fallback-config" = "d432c3e5ae4a7a4485fdc69f8d4789140125c78d35b89d0b2493ccef0bbcf739",
            "checksum/config" = "f6adb4c80ecb4ccb1ddf90f3364c08b86205936a6de06f43e0f3216ced2a89e3",
          },
          labels = {
            "app.kubernetes.io/component" = "alertmanager",
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
                "-target=alertmanager",
                "-config.expand-env=true",
                "-config.file=/etc/mimir/mimir.yaml"
              ],
              image = "grafana/mimir:2.12.0",
              imagePullPolicy = "IfNotPresent",
              name = "alertmanager",
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
                  cpu = "10m",
                  memory = "32Mi",
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
                  mountPath = "/configs/",
                  name = "alertmanager-fallback-config",
                },
                {
                  mountPath = "/tmp",
                  name = "tmp",
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
          terminationGracePeriodSeconds = 60,
          topologySpreadConstraints = [
            {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/component" = "alertmanager",
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
            { emptyDir = {}, name = "tmp", },
            {
              emptyDir = {},
              name = "active-queries",
            },
            {
              configMap = {
                name = "mimir-distributed-alertmanager-fallback-config",
              },
              name = "alertmanager-fallback-config",
            }
          ],
        },
      },
      updateStrategy = { type = "RollingUpdate", },
      volumeClaimTemplates = [
        {
          metadata = { name = "storage", },
          spec = {
            accessModes = ["ReadWriteOnce"],
            resources = { requests = { storage = "1Gi", }, },
          },
        }
      ],
    },
  },
}
