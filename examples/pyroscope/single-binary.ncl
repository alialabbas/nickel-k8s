let t = import "../../transfomers.ncl" in
fun inputs =>
  let
    _labels = {
      "app.kubernetes.io/component" | force = "single-binary",
      "app.kubernetes.io/instance" = "pyroscope",
      "app.kubernetes.io/name" | force = "pyroscope",
      "app.kubernetes.io/part-of" | force = "memberlist",
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
        selector = {
          "app.kubernetes.io/instance" = "pyroscope",
          "app.kubernetes.io/name" = "pyroscope",
          "app.kubernetes.io/part-of" = "memberlist",
        },
        type = "ClusterIP",
        publishNotReadyAddresses = true,
      },
    },

    single-binary-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = {
          "app.kubernetes.io/component" = "single-binary",
          "app.kubernetes.io/instance" = "pyroscope",
          "app.kubernetes.io/name" = "pyroscope",
          "app.kubernetes.io/part-of" = "memberlist",
          "app.kubernetes.io/version" = inputs.version,
        },
        name = "pyroscope",
      },
      spec = {
        podManagementPolicy = "Parallel",
        serviceName = single-binary-headless-service.metadata.name,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels =
            # has to be this way if we want a consumer to add or modify these value while allowing them to propagate correctly
            labels_to_selectors metadata.labels
        },
        template = {
          metadata = {
            labels = single-binary-statefulset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-config.file=/etc/pyroscope/config/config.yaml",
                ],
                image = "docker.io/grafana/pyroscope:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                name = "single-binary",
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
    single-binary-poddisruptionbudget = t.PodDisruptionBudgetForWorkload single-binary-statefulset ('maxUnavailable 1),
    single-binary-service = t.ServiceFromDeployment single-binary-statefulset,
    single-binary-headless-service = t.HeadlessServiceForWorkload single-binary-statefulset,
    # TODO: HPA
  }
