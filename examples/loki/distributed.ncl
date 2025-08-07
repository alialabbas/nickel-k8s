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
          "name" => true,
          "rollout-group" => true,
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
        name = "loki-distributor",
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
            labels = distributor-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=distributor"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
    distributor-headless-service = t.HeadlessServiceForWorkload distributor-deployment,
    distributor-poddisruptionbudget = t.PodDisruptionBudgetForWorkload distributor-deployment ('maxUnavailable 2),
    distributor-service = t.ServiceFromDeployment distributor-deployment,

    compactor-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "compactor",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "loki-compactor",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors compactor-statefulset.metadata.labels,
        },
        serviceName = "loki-compactor-headless",
        template = {
          metadata = {
            labels = compactor-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=compactor"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
      },
    },
    compactor-service = t.ServiceFromDeployment compactor-statefulset,

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
        name = "loki-query-frontend",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors query-frontend-deployment.metadata.labels,
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
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=query-frontend"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
    query-frontend-headless-service = t.HeadlessServiceForWorkload query-frontend-deployment,
    query-frontend-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-frontend-deployment ('maxUnavailable 1),
    query-frontend-service = t.ServiceFromDeployment query-frontend-deployment,

    querier-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels =
          _labels
          & {
            "app.kubernetes.io/component" | force = "querier",
            "app.kubernetes.io/part-of" | force = "memberlist",
          },
        name = "loki-querier",
      },
      spec = {
        serviceName = querier-headless-svc.metadata.name,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors querier-statefulset.metadata.labels,
        },
        template = {
          metadata = {
            labels = querier-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=querier"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
    querier-poddisruptionbudget = t.PodDisruptionBudgetForWorkload querier-statefulset ('maxUnavailable 2),
    querier-headless-svc = t.HeadlessServiceForWorkload querier-statefulset,
    querier-service = t.ServiceFromDeployment querier-statefulset,

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
        name = "loki-query-scheduler",
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
            labels = query-scheduler-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=query-scheduler"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
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
    query-scheduler-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-scheduler-deployment ('maxUnavailable 1),
    query-scheduler-service = t.ServiceFromDeployment query-scheduler-deployment,
  }
  & (
    if inputs.config.ingester.lifecycler.ring.zone_awareness_enabled then
      {
        serviceaccount = {},
        configmap = {},
        runtime-configmap = {},

        ingester-zone-a-statefulset = {
          apiVersion = "apps/v1",
          kind = "StatefulSet",
          metadata = {
            annotations = { rollout-max-unavailable = "1", },
            labels =
              _labels
              & {
                "app.kubernetes.io/part-of" | force = "memberlist",
                "app.kubernetes.io/component" | force = "ingester",
                name = "loki-ingester-zone-a",
                rollout-group = "ingester",
              },
            name = "loki-ingester-zone-a",
          },
          spec = {
            podManagementPolicy = "Parallel",
            replicas = 1,
            revisionHistoryLimit = 10,
            selector = {
              matchLabels = labels_to_selectors ingester-zone-a-statefulset.metadata.labesl,
            },
            serviceName = ingester-zone-a-headless-service.metadata.name,
            template = {
              metadata = {
                labels = ingester-zone-a-statefulset.metadata.labels,
              },
              spec = {
                containers = [
                  {
                    args = [
                      "-config.file=/etc/loki/config/config.yaml",
                      "-target=ingester"
                    ],
                    image = "docker.io/grafana/loki:%{inputs.version}",
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
            updateStrategy = { type = "RollingUpdate", },
          },
        },
        ingester-zone-a-headless-service = t.HeadlessServiceForWorkload ingester-zone-a-statefulset,

        ingester-zone-b-statefulset = {
          apiVersion = "apps/v1",
          kind = "StatefulSet",
          metadata = {
            annotations = { rollout-max-unavailable = "1", },
            labels =
              _labels
              & {
                "app.kubernetes.io/part-of" | force = "memberlist",
                "app.kubernetes.io/component" | force = "ingester",
                name = "loki-ingester-zone-b",
                rollout-group = "ingester",
              },
            name = "loki-ingester-zone-b",
          },
          spec = {
            podManagementPolicy = "Parallel",
            replicas = 1,
            revisionHistoryLimit = 10,
            selector = {
              matchLabels = labels_to_selectors metadata.labels,
            },
            serviceName = ingester-zone-b-headless-service.metadata.name,
            template = {
              metadata = {
                labels = ingester-zone-b-statefulset.metadata.labels,
              },
              spec = {
                containers = [
                  {
                    args = [
                      "-config.file=/etc/loki/config/config.yaml",
                      "-target=query-scheduler"
                    ],
                    image = "docker.io/grafana/loki:%{inputs.version}",
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
            updateStrategy = { type = "RollingUpdate", },
          },
        },
        ingester-zone-b-headless-service = t.HeadlessServiceForWorkload ingester-zone-b-statefulset,

        ingester-zone-c-statefulset = {
          apiVersion = "apps/v1",
          kind = "StatefulSet",
          metadata = {
            annotations = { rollout-max-unavailable = "1", },
            labels =
              _labels
              & {
                "app.kubernetes.io/part-of" | force = "memberlist",
                "app.kubernetes.io/component" | force = "ingester",
                name = "loki-ingester-zone-c",
                rollout-group = "ingester",
              },
            name = "loki-ingester-zone-c",
          },
          spec = {
            podManagementPolicy = "Parallel",
            replicas = 1,
            revisionHistoryLimit = 10,
            selector = {
              matchLabels = labels_to_selectors ingester-zone-c-statefulset.metadata.labels,
            },
            serviceName = ingester-zone-c-headless-service.metadata.name,
            template = {
              metadata = {
                labels =
                  _labels
                  & {
                    name = "loki-ingester-zone-c",
                    rollout-group = "ingester",
                  },
              },
              spec = {
                containers = [
                  {
                    args = [
                      "-config.file=/etc/loki/config/config.yaml",
                      "-target=query-scheduler"
                    ],
                    image = "docker.io/grafana/loki:%{inputs.version}",
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
            updateStrategy = { type = "RollingUpdate", },
          },
        },
        ingester-zone-c-headless-service = t.HeadlessServiceForWorkload ingester-zone-c-statefulset,

        ingester-rollout-poddisruptionbudget = {
          apiVersion = "policy/v1",
          kind = "PodDisruptionBudget",
          metadata = {
            labels = _labels,
            name = "loki-ingester-rollout",
          },
          spec = {
            maxUnavailable = 1,
            selector = { matchLabels = { rollout-group = "ingester" } },
          },
        },
      }
    else
      {
        serviceaccount = {},
        configmap = {},
        runtime-configmap = {},

        ingester-statefulset = {
          apiVersion = "apps/v1",
          kind = "StatefulSet",
          metadata = {
            labels = _labels,
            name = "loki-ingester",
          },
          spec = {
            podManagementPolicy = "Parallel",
            replicas = 1,
            selector = {
              matchLabels = labels_to_selectors ingester-statefulset.metadata.labels,
            },
            serviceName = "loki-ingester",
            template = {
              metadata = {
                labels = ingester-statefulset.metadata.labels,
              },
              spec = {
                containers = [
                  {
                    args = [
                      "-config.file=/etc/loki/config/config.yaml",
                      "-target=ingester"
                    ],
                    image = "docker.io/grafana/loki:%{inputs.version}",
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
      }
  )
