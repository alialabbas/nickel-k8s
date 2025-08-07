let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "pyroscope",
      "app.kubernetes.io/name" | force = "pyroscope",
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
        "config.yaml" = (std.serialize 'Yaml inputs.config),
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "pyroscope",
      },
    },
    overrides-config-configmap = {
      apiVersion = "v1",
      data = { "overrides.yaml" = "overrides:\n  {}\n", },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "pyroscope-runtime",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = configmap.metadata.name,
      },
    },
    memberlist-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = _labels,
        name = "pyroscope-memberlist",
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            name = "tcp",
            port = inputs.config.memberlist.advertise_port,
            protocol = "TCP",
            targetPort = "http-memberlist",
          }
        ],
        selector =
          labels_to_selectors metadata.labels
          & {
            "app.kubernetes.io/part-of" = "memberlist",
          },
        type = "ClusterIP",
        publishNotReadyAddresses = true,
      },
    },

    distributor-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "distributor",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "pyroscope-distributor",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels
        },
        template = {
          metadata = {
            labels = distributor-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=distributor",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    distributor-service = t.ServiceFromDeployment distributor-deployment,
    distributor-pdb = t.PodDisruptionBudgetForWorkload distributor-deployment ('maxUnavailable 1),
    distributor-headless-svc = t.HeadlessServiceForWorkload distributor-deployment,

    query-frontend-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "query-frontend",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },

        name = "pyroscope-query-frontend",
      },
      spec = {
        minReadySeconds = 10,
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
            labels = query-frontend-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=query-frontend",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    query-frontend-service = t.ServiceFromDeployment query-frontend-deployment,
    query-frontend-pdb = t.PodDisruptionBudgetForWorkload query-frontend-deployment ('maxUnavailable 1),
    query-frontend-headless-svc = t.HeadlessServiceForWorkload query-frontend-deployment,

    querier-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "querier",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "pyroscope-querier",
      },
      spec = {
        minReadySeconds = 10,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors querier-deployment.metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = querier-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=querier",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    querier-service = t.ServiceFromDeployment querier-deployment,
    querier-pdb = t.PodDisruptionBudgetForWorkload querier-deployment ('maxUnavailable 1),
    querier-headless-svc = t.HeadlessServiceForWorkload querier-deployment,

    query-scheduler-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "query-scheduler",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "pyroscope-query-scheduler",
      },
      spec = {
        minReadySeconds = 10,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors query-scheduler-deployment.metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = query-scheduler-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=query-scheduler",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    query-scheduler-service = t.ServiceFromDeployment query-scheduler-deployment,
    query-scheduler-pdb = t.PodDisruptionBudgetForWorkload query-scheduler-deployment ('maxUnavailable 1),
    query-scheduler-headless-svc = t.HeadlessServiceForWorkload query-scheduler-deployment,

    store-gateway-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "store-gateway",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "pyroscope-store-gateway",
      },
      spec = {
        serviceName = store-gateway-headless-svc.metadata.name,
        minReadySeconds = 10,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        template = {
          metadata = {
            labels = store-gateway-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=store-gateway",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    store-gateway-service = t.ServiceFromDeployment store-gateway-statefulset,
    store-gateway-pdb = t.PodDisruptionBudgetForWorkload store-gateway-statefulset ('maxUnavailable 1),
    store-gateway-headless-svc = t.HeadlessServiceForWorkload store-gateway-statefulset,

    ingester-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "ingester",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "pyroscope-ingester",
      },
      spec = {
        serviceName = ingester-headless-svc.metadata.name,
        minReadySeconds = 10,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        template = {
          metadata = {
            labels = ingester-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                  "-target=ingester",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
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
                    containerPort = inputs.config.memberlist.bind_port,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = { requests = { memory = "100Mi", cpu = 0.1 } },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/pyroscope/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/pyroscope-runtime",
                    name = "runtime-config",
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
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              {
                configMap = { name = overrides-config-configmap.metadata.name, },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    ingester-service = t.ServiceFromDeployment ingester-statefulset,
    ingester-pdb = t.PodDisruptionBudgetForWorkload ingester-statefulset ('maxUnavailable 1),
    ingester-headless-svc = t.HeadlessServiceForWorkload ingester-statefulset,
  }
