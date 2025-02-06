let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "distributor",
    _labels = utils.common_labels version "distributor",
  in
  {
    distributor-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels,
        name = "loki-distributor",
      },
      spec = {
        replicas = 3,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = _selectors,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = _labels,
          },
          spec = {
            affinity = {
              podAntiAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = [
                  {
                    labelSelector = {
                      matchLabels = {
                        "app.kubernetes.io/component" = "distributor",
                      },
                    },
                    topologyKey = "kubernetes.io/hostname",
                  }
                ],
              },
            },
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=distributor",
                  "-distributor.zone-awareness-enabled=true" # TODO: this can be an option for the distributed mode with topology spread
                ],
                image = "docker.io/grafana/loki:%{version}",
                imagePullPolicy = "IfNotPresent",
                name = "distributor",
                ports = [
                  {
                    containerPort = 3100,
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
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = {
                    path = "/ready",
                    port = "http-metrics",
                  },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                resources = {},
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
                    mountPath = "/etc/loki/runtime-config",
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
            serviceAccountName = "loki",
            terminationGracePeriodSeconds = 30,
            volumes = [
              {
                configMap = {
                  items = [
                    {
                      key = "config.yaml",
                      path = "config.yaml",
                    }
                  ],
                  name = "loki",
                },
                name = "config",
              },
              {
                configMap = { name = "loki-runtime", },
                name = "runtime-config",
              }
            ],
          },
        },
      },
    },
    distributor-headless-service = t.HeadlessServiceForWorkload distributor-deployment,
    distributor-poddisruptionbudget = t.PodDisruptionBudgetForWorkload distributor-deployment ('maxUnavailable 2),
    distributor-service = t.ServiceFromDeployment distributor-deployment,
  }
