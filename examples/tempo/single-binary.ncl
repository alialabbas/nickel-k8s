let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "tempo",
      "app.kubernetes.io/name" | force = "tempo",
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
          _ => false,
        }
      ),
  in
  {
    runtime-configmap = {
      apiVersion = "v1",
      data = { "overrides.yaml" = "\noverrides:\n  null\n", },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "tempo-runtime",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = false,
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = "tempo",
      },
    },
    configmap = {
      apiVersion = "v1",
      data = {
        "query.yaml" = "backend: 127.0.0.1:3200\n",
        "tempo.yaml" = std.serialize 'Yaml inputs.config,
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "tempo",
      },
    },
    gossip-ring-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = _labels,
        name = "tempo-gossip-ring",
      },
      spec = {
        clusterIP = "None",
        ipFamilies = ["IPv4"],
        ipFamilyPolicy = "SingleStack",
        ports = [
          {
            name = "gossip-ring",
            port = inputs.config.memberlist.bind_port,
            protocol = "TCP",
            targetPort = inputs.config.memberlist.bind_port,
          }
        ],
        publishNotReadyAddresses = true,
        selector = labels_to_selectors metadata.labels,
        type = "ClusterIP",
      },
    },

    single-binary-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels,
        name = "tempo",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labesl,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = _labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/tempo/config/tempo.yaml",
                  "-target=all",
                ],
                image = "docker.io/grafana/tempo:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "tempo",
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
                  },
                  # TODO: this ideally needs to be from the config but that's just otlp parsing magic
                  {
                    containerPort = 4317,
                    name = "otlp-grpc",
                  },
                  {
                    containerPort = 14250,
                    name = "jaeger-grpc",
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
                    mountPath = "/etc/tempo/config",
                    name = "config",
                  },
                  {
                    mountPath = "/var/tempo-runtime",
                    name = "runtime-config",
                  },
                  {
                    name = "data",
                    mountPath = "/var/tempo",
                  },
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
                configMap = { name = runtime-configmap.metadata.name, },
                name = "runtime-config",
              },
              {
                name = "data",
                emptyDir = {},
              }
            ],
          },
        },
      },
    },
    single-binary-poddisruptionbudget = t.PodDisruptionBudgetForWorkload single-binary-statefulset ('maxUnavailable 1),
    single-binary-service = t.ServiceFromDeployment single-binary-statefulset,
    # TODO: HPA
  }
