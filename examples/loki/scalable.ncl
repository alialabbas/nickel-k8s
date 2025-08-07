let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "loki",
      "app.kubernetes.io/name" | force = "loki",
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
          _ => false,
        }
      ),
  in
  {
    configmap = {
      apiVersion = "v1",
      data = {
        "config.yaml" = (std.serialize 'Yaml inputs.config)
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "loki",
      },
    },
    memberlist-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = _labels & { "app.kubernetes.io/part-of" | force = "memberlist", },
        name = "loki-memberlist",
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            name = "tcp",
            port = 7946,
            protocol = "TCP",
            targetPort = "http-memberlist",
          }
        ],
        selector = labels_to_selectors metadata.labels,
        type = "ClusterIP",
        publishNotReadyAddresses = true,
      },
    },
    runtime-configmap = {
      apiVersion = "v1",
      data = { "runtime-config.yaml" = "{}\n", },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "loki-runtime",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = true,
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = "loki",
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
        name = "loki-read",
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
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=read"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
                resources = { requests = { cpu = 0.1, memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/loki/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/loki-runtime",
                    name = "runtime-config",
                  },
                  {
                    name = "data",
                    mountPath = "/var/loki"
                  }
                ],
              }
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
                configMap = { name = configmap.metadata.name },
                name = "config",
              },
              {
                configMap = { name = runtime-configmap.metadata.name },
                name = "runtime-config",
              },
              {
                name = "data",
                emptyDir = {}
              }
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
        name = "loki-write",
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
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=write"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
                resources = { requests = { cpu = 0.1, memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/loki/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/loki-runtime",
                    name = "runtime-config",
                  },
                  {
                    name = "data",
                    mountPath = "/var/loki"
                  }
                ],
              }
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
                configMap = { name = configmap.metadata.name },
                name = "config",
              },
              {
                configMap = { name = runtime-configmap.metadata.name },
                name = "runtime-config",
              },
              {
                name = "data",
                emptyDir = {}
              }
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

        name = "loki-backend",
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
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=backend"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
                resources = { requests = { cpu = 0.1, memory = "200Mi" } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/loki/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/loki-runtime",
                    name = "runtime-config",
                  },
                  {
                    name = "data",
                    mountPath = "/var/loki"
                  }
                ],
              }
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
                configMap = { name = configmap.metadata.name },
                name = "config",
              },
              {
                configMap = { name = runtime-configmap.metadata.name },
                name = "runtime-config",
              },
              {
                name = "data",
                emptyDir = {}
              }
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
  }
