{
  ingester-headless-service = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        "prometheus.io/service-monitor" = "false",
      },
      name = "mimir-distributed-ingester-headless",
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
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
      },
      type = "ClusterIP",
    },
  },
  ingester-poddisruptionbudget = {
    apiVersion = "policy/v1",
    kind = "PodDisruptionBudget",
    metadata = {
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
      },
      name = "mimir-distributed-ingester",
      namespace = "default",
    },
    spec = {
      maxUnavailable = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "ingester",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
        },
      },
    },
  },
  ingester-zone-a-service = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-a",
        rollout-group = "ingester",
        zone = "zone-a",
      },
      name = "mimir-distributed-ingester-zone-a",
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
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
        rollout-group = "ingester",
        zone = "zone-a",
      },
      type = "ClusterIP",
    },
  },
  ingester-zone-a-statefulset = {
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    metadata = {
      annotations = { rollout-max-unavailable = "50", },
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-a",
        rollout-group = "ingester",
        zone = "zone-a",
      },
      name = "mimir-distributed-ingester-zone-a",
      namespace = "default",
    },
    spec = {
      podManagementPolicy = "Parallel",
      replicas = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "ingester",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          rollout-group = "ingester",
          zone = "zone-a",
        },
      },
      serviceName = "mimir-distributed-ingester-headless",
      template = {
        metadata = {
          annotations = {
            "checksum/config" = "f6adb4c80ecb4ccb1ddf90f3364c08b86205936a6de06f43e0f3216ced2a89e3",
          },
          labels = {
            "app.kubernetes.io/component" = "ingester",
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/managed-by" = "Helm",
            "app.kubernetes.io/name" = "mimir",
            "app.kubernetes.io/part-of" = "memberlist",
            "app.kubernetes.io/version" = "2.12.0",
            "helm.sh/chart" = "mimir-distributed-5.3.0",
            name = "ingester-zone-a",
            rollout-group = "ingester",
            zone = "zone-a",
          },
          namespace = "default",
        },
        spec = {
          containers = [
            {
              args = [
                "-target=ingester",
                "-config.expand-env=true",
                "-config.file=/etc/mimir/mimir.yaml",
                "-ingester.ring.instance-availability-zone=zone-a"
              ],
              env = [
                {
                  name = "JAEGER_REPORTER_MAX_QUEUE_SIZE",
                  value = "1000",
                }
              ],
              image = "grafana/mimir:2.12.0",
              imagePullPolicy = "IfNotPresent",
              name = "ingester",
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
                initialDelaySeconds = 60,
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
          terminationGracePeriodSeconds = 240,
          topologySpreadConstraints = [
            {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/component" = "ingester",
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
            {
              emptyDir = {},
              name = "active-queries",
            }
          ],
        },
      },
      updateStrategy = { type = "OnDelete", },
      volumeClaimTemplates = [
        {
          metadata = { name = "storage", },
          spec = {
            accessModes = ["ReadWriteOnce"],
            resources = { requests = { storage = "2Gi", }, },
          },
        }
      ],
    },
  },
  ingester-zone-b-service = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-b",
        rollout-group = "ingester",
        zone = "zone-b",
      },
      name = "mimir-distributed-ingester-zone-b",
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
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
        rollout-group = "ingester",
        zone = "zone-b",
      },
      type = "ClusterIP",
    },
  },
  ingester-zone-b-statefulset = {
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    metadata = {
      annotations = { rollout-max-unavailable = "50", },
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-b",
        rollout-group = "ingester",
        zone = "zone-b",
      },
      name = "mimir-distributed-ingester-zone-b",
      namespace = "default",
    },
    spec = {
      podManagementPolicy = "Parallel",
      replicas = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "ingester",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          rollout-group = "ingester",
          zone = "zone-b",
        },
      },
      serviceName = "mimir-distributed-ingester-headless",
      template = {
        metadata = {
          annotations = {
            "checksum/config" = "f6adb4c80ecb4ccb1ddf90f3364c08b86205936a6de06f43e0f3216ced2a89e3",
          },
          labels = {
            "app.kubernetes.io/component" = "ingester",
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/managed-by" = "Helm",
            "app.kubernetes.io/name" = "mimir",
            "app.kubernetes.io/part-of" = "memberlist",
            "app.kubernetes.io/version" = "2.12.0",
            "helm.sh/chart" = "mimir-distributed-5.3.0",
            name = "ingester-zone-b",
            rollout-group = "ingester",
            zone = "zone-b",
          },
          namespace = "default",
        },
        spec = {
          containers = [
            {
              args = [
                "-target=ingester",
                "-config.expand-env=true",
                "-config.file=/etc/mimir/mimir.yaml",
                "-ingester.ring.instance-availability-zone=zone-b"
              ],
              env = [
                {
                  name = "JAEGER_REPORTER_MAX_QUEUE_SIZE",
                  value = "1000",
                }
              ],
              image = "grafana/mimir:2.12.0",
              imagePullPolicy = "IfNotPresent",
              name = "ingester",
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
                initialDelaySeconds = 60,
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
          terminationGracePeriodSeconds = 240,
          topologySpreadConstraints = [
            {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/component" = "ingester",
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
            {
              emptyDir = {},
              name = "active-queries",
            }
          ],
        },
      },
      updateStrategy = { type = "OnDelete", },
      volumeClaimTemplates = [
        {
          metadata = { name = "storage", },
          spec = {
            accessModes = ["ReadWriteOnce"],
            resources = { requests = { storage = "2Gi", }, },
          },
        }
      ],
    },
  },
  ingester-zone-c-service = {
    apiVersion = "v1",
    kind = "Service",
    metadata = {
      annotations = {},
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-c",
        rollout-group = "ingester",
        zone = "zone-c",
      },
      name = "mimir-distributed-ingester-zone-c",
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
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/name" = "mimir",
        rollout-group = "ingester",
        zone = "zone-c",
      },
      type = "ClusterIP",
    },
  },
  ingester-zone-c-statefulset = {
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    metadata = {
      annotations = { rollout-max-unavailable = "50", },
      labels = {
        "app.kubernetes.io/component" = "ingester",
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "mimir",
        "app.kubernetes.io/part-of" = "memberlist",
        "app.kubernetes.io/version" = "2.12.0",
        "helm.sh/chart" = "mimir-distributed-5.3.0",
        name = "ingester-zone-c",
        rollout-group = "ingester",
        zone = "zone-c",
      },
      name = "mimir-distributed-ingester-zone-c",
      namespace = "default",
    },
    spec = {
      podManagementPolicy = "Parallel",
      replicas = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "ingester",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          rollout-group = "ingester",
          zone = "zone-c",
        },
      },
      serviceName = "mimir-distributed-ingester-headless",
      template = {
        metadata = {
          annotations = {
            "checksum/config" = "f6adb4c80ecb4ccb1ddf90f3364c08b86205936a6de06f43e0f3216ced2a89e3",
          },
          labels = {
            "app.kubernetes.io/component" = "ingester",
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/managed-by" = "Helm",
            "app.kubernetes.io/name" = "mimir",
            "app.kubernetes.io/part-of" = "memberlist",
            "app.kubernetes.io/version" = "2.12.0",
            "helm.sh/chart" = "mimir-distributed-5.3.0",
            name = "ingester-zone-c",
            rollout-group = "ingester",
            zone = "zone-c",
          },
          namespace = "default",
        },
        spec = {
          containers = [
            {
              args = [
                "-target=ingester",
                "-config.expand-env=true",
                "-config.file=/etc/mimir/mimir.yaml",
                "-ingester.ring.instance-availability-zone=zone-c"
              ],
              env = [
                {
                  name = "JAEGER_REPORTER_MAX_QUEUE_SIZE",
                  value = "1000",
                }
              ],
              image = "grafana/mimir:2.12.0",
              imagePullPolicy = "IfNotPresent",
              name = "ingester",
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
                initialDelaySeconds = 60,
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
          terminationGracePeriodSeconds = 240,
          topologySpreadConstraints = [
            {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/component" = "ingester",
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
            {
              emptyDir = {},
              name = "active-queries",
            }
          ],
        },
      },
      updateStrategy = { type = "OnDelete", },
      volumeClaimTemplates = [
        {
          metadata = { name = "storage", },
          spec = {
            accessModes = ["ReadWriteOnce"],
            resources = { requests = { storage = "2Gi", }, },
          },
        }
      ],
    },
  },
}
