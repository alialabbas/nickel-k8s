let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "mimir",
      "app.kubernetes.io/name" | force = "mimir",
      "app.kubernetes.io/version" = inputs.version,
    },
    labels_to_selectors = fun labels =>
      labels
      |> std.record.filter (fun k _ =>
        k
        |> match {
          "app.kubernetes.io/component" => true,
          "app.kubernetes.io/instance" => true,
          "app.kubernetes.io/name" => true,
          "app.kubernetes.io/part-of" => true,
          _ => false,
        }
      ),
  in
  {
    config = {
      apiVersion = "v1",
      data = {
        "mimir.yaml" = std.serialize 'Yaml inputs.config,
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "mimir",
      },
    },
    gossip-ring-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = _labels & { "app.kubernetes.io/part-of" = "memberlist", },
        name = "mimir-gossip-ring",
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            appProtocol = "tcp",
            name = "gossip-ring",
            port = 7946,
            protocol = "TCP",
            targetPort = 7946,
          }
        ],
        publishNotReadyAddresses = true,
        selector = labels_to_selectors metadata.labels,
        type = "ClusterIP",
      },
    },
    runtime-config = {
      apiVersion = "v1",
      data = {
        "runtime.yaml" = std.serialize 'Yaml ({}),
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "mimir-runtime",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        annotations = {},
        labels = _labels,
        name = "mimir",
      },
    },

    distributor-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "distributor", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-distributor",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = "15%", maxUnavailable = 0, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            labels = distributor-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=distributor",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "distributor",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
      },
    },
    distributor-headless-service = t.HeadlessServiceForWorkload distributor-deployment,
    distributor-poddisruptionbudget = t.PodDisruptionBudgetForWorkload distributor-deployment ('maxUnavailable 1),
    distributor-service = t.ServiceFromDeployment distributor-deployment,

    compactor-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "compactor", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-compactor",
      },
      spec = {
        podManagementPolicy = "OrderedReady",
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        serviceName = "mimir-compactor",
        template = {
          metadata = {
            labels = compactor-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=compactor",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "compactor",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
        updateStrategy = { type = "RollingUpdate", },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "storage", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "2Gi", }, },
            },
          }
        ],
      },
    },
    compactor-poddisruptionbudget = t.PodDisruptionBudgetForWorkload compactor-statefulset ('maxUnavailable 1),
    compactor-service = t.ServiceFromDeployment compactor-statefulset,

    # TODO: zone awareness
    store-gateway-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "store-gateway", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-store-gateway",
      },
      spec = {
        podManagementPolicy = "OrderedReady",
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors store-gateway-statefulset.metadata.labels,
        },
        serviceName = "mimir-store-gateway",
        template = {
          metadata = {
            labels = store-gateway-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=store-gateway",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "store-gateway",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
        updateStrategy = { type = "RollingUpdate", },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "storage", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "2Gi", }, },
            },
          }
        ],
      },
    },
    store-gateway-poddisruptionbudget = t.PodDisruptionBudgetForWorkload store-gateway-statefulset ('maxUnavailable 1),
    store-gateway-service = t.ServiceFromDeployment store-gateway-statefulset,

    # TODO: zone awareness
    ingester-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "ingester", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-ingester",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors ingester-statefulset.metadata.labels,
        },
        serviceName = "mimir-ingester",
        template = {
          metadata = {
            labels = ingester-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=ingester",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "ingester",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
        updateStrategy = { type = "RollingUpdate", },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "storage", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "2Gi", }, },
            },
          }
        ],
      },
    },
    ingester-poddisruptionbudget = t.PodDisruptionBudgetForWorkload ingester-statefulset ('maxUnavailable 1),
    ingester-service = t.ServiceFromDeployment ingester-statefulset,
    ingester-headless-service = t.HeadlessServiceForWorkload ingester-statefulset,

    query-frontend-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "query-frontend", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-query-frontend",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = "15%", maxUnavailable = 0, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            labels = query-frontend-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=query-frontend",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "query-frontend",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
      },
    },
    query-frontend-headless-service = t.HeadlessServiceForWorkload query-frontend-deployment,
    query-frontend-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-frontend-deployment ('maxUnavailable 1),
    query-frontend-service = t.ServiceFromDeployment query-frontend-deployment,

    querier-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "querier", "app.kubernetes.io/part-of" = "memberlist" },
        name = "mimir-querier",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = "15%", maxUnavailable = 0, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            labels = querier-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=querier",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "querier",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
      },
    },
    querier-headless-service = t.HeadlessServiceForWorkload querier-deployment,
    querier-poddisruptionbudget = t.PodDisruptionBudgetForWorkload querier-deployment ('maxUnavailable 1),
    querier-service = t.ServiceFromDeployment querier-deployment,

    query-scheduler-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels & { "app.kubernetes.io/component" = "query-scheduler" },
        name = "mimir-query-scheduler",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = "15%", maxUnavailable = 0, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            labels = query-scheduler-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=query-scheduler",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "query-scheduler",
                ports = [
                  {
                    containerPort = inputs.config.server.http_listen_port,
                    name = "http",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.server.grpc_listen_port,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = inputs.config.memberlist.advertise_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/mimir/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/mimir",
                    name = "runtime-config",
                  },
                  {
                    name = "storage",
                    mountPath = "/data",
                  },
                  {
                    name = "active-queries",
                    mountPath = "/active-query-tracker",
                  },
                ],
              },
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = serviceaccount.metadata.name,
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = runtime-config.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "active-queries",
                emptyDir = {},
              },
              {
                name = "storage",
                emptyDir = {},
              },
            ],
          },
        },
      },
    },
    query-scheduler-headless-service = t.HeadlessServiceForWorkload query-scheduler-deployment,
    query-scheduler-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-scheduler-deployment ('maxUnavailable 1),
    query-scheduler-service = t.ServiceFromDeployment query-scheduler-deployment,
  }
