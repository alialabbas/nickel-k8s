let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "mimir",
      "app.kubernetes.io/name" | force = "mimir",
      "app.kubernetes.io/version" = inputs.version,
      "app.kubernetes.io/component" = "single-binary",
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

    single-binary-statefulset = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels,
        name = "mimir",
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
            labels = single-binary-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/mimir/config/mimir.yaml",
                  "-target=all",
                ],
                image = "docker.io/grafana/mimir:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "mimir",
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
    single-binary-poddisruptionbudget = t.PodDisruptionBudgetForWorkload single-binary-statefulset ('maxUnavailable 1),
    single-binary-service = t.ServiceFromDeployment single-binary-statefulset,
    single-binary-svc-headless = t.HeadlessServiceForWorkload single-binary-statefulset,
    # TODO: HPA
  }
