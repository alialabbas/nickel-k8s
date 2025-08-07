let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "mimir",
      "app.kubernetes.io/name" | force = "mimir",
      "app.kubernetes.io/version" = inputs.version,
      "app.kubernetes.io/part-of" = "memberlist",
    },
    labels_to_selectors = fun labels =>
      labels
      |> std.record.filter (fun k _ =>
        k
        |> match {
          "app.kubernetes.io/component" => true,
          "app.kubernetes.io/instance" => true,
          "app.kubernetes.io/name" => true,
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
        labels = _labels,
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
    read-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/part-of" | force = "memberlist",
            "app.kubernetes.io/component" | force = "read",
          },
        name = "mimir-read",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = read-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=read",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "read",
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
    read-headless-service = t.HeadlessServiceForWorkload read-deployment,
    read-poddisruptionbudget = t.PodDisruptionBudgetForWorkload read-deployment ('maxUnavailable 2),
    read-service = t.ServiceFromDeployment read-deployment,

    write-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/part-of" | force = "memberlist",
            "app.kubernetes.io/component" | force = "write",
          },
        name = "mimir-write",
      },
      spec = {
        persistentVolumeClaimRetentionPolicy = { whenDeleted = "Delete", whenScaled = "Delete", },
        podManagementPolicy = "Parallel",
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        serviceName = write-headless-service.metadata.name,
        template = {
          metadata = {
            labels = write-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=write",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "write",
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
        updateStrategy = { rollingUpdate = { partition = 0, }, },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "data", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "10Gi", }, },
            },
          }
        ],
      },
    },
    write-headless-service = t.HeadlessServiceForWorkload write-statefulset,
    write-poddisruptionbudget = t.PodDisruptionBudgetForWorkload write-statefulset ('maxUnavailable 1),
    write-service = t.ServiceFromDeployment write-statefulset,

    backend-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/part-of" | force = "memberlist",
            "app.kubernetes.io/component" | force = "backend",
          },
        name = "mimir-backend",
      },
      spec = {
        persistentVolumeClaimRetentionPolicy = { whenDeleted = "Delete", whenScaled = "Delete", },
        podManagementPolicy = "Parallel",
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        serviceName = backend-headless-service.metadata.name,
        template = {
          metadata = {
            labels = backend-statefulset.metadata.labels,
          },
          spec = {
            automountServiceAccountToken = true,
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=backend",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "backend",
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
                  {
                    name = "alertmanager-fallback-config",
                    mountPath = "/configs",
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
            serviceAccountName = "mimir",
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = { name = config.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = alertmanager-config.metadata.name, },
                name = "alertmanager-fallback-config",
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
        updateStrategy = { rollingUpdate = { partition = 0, }, },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "data", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "10Gi", }, },
            },
          }
        ],
      },
    },
    backend-headless-service = t.HeadlessServiceForWorkload backend-statefulset,
    backend-poddisruptionbudget = t.PodDisruptionBudgetForWorkload backend-statefulset ('maxUnavailable 1),
    backend-service = t.ServiceFromDeployment backend-statefulset,

    # backend also runs alertmanager
    alertmanager-config = {
      apiVersion = "v1",
      data = {
        "alertmanager_fallback_config.yaml" = "receivers:\n    - name: default-receiver\nroute:\n    receiver: default-receiver\n",
      },
      kind = "ConfigMap",
      metadata = {
        annotations = {},
        labels = _labels,
        name = "alertmanager-fallback-config",
      },
    },
  }
