let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "loki",
      "app.kubernetes.io/name" | force = "loki",
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
        labels = _labels,
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
    single-binary-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels,
        name = "loki",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors single-binary-statefulset.metadata.labels,
        },
        template = {
          metadata = {
            labels = single-binary-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=all"
                ],
                image = "docker.io/grafana/loki:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "loki",
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
    single-binary-poddisruptionbudget = t.PodDisruptionBudgetForWorkload single-binary-statefulset ('maxUnavailable 1),
    single-binary-service = t.ServiceFromDeployment single-binary-statefulset,
    # TODO: HPA
  }
