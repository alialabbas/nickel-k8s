let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "read",
    _labels = utils.common_labels version "read",
  in
  {
    loki-read-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels,
        name = "loki-read",
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
                        "app.kubernetes.io/component" = "read",
                      },
                    },
                    topologyKey = "kubernetes.io/hostname",
                  }
                ],
              },
            },
            automountServiceAccountToken = true,
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=read",
                  "-legacy-read-mode=false",
                  "-common.compactor-grpc-address=loki-backend.default.svc.cluster.local:9095"
                ],
                image = "docker.io/grafana/loki:" ++ version,
                imagePullPolicy = "IfNotPresent",
                name = "loki",
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
                  },
                  {
                    mountPath = "/tmp",
                    name = "tmp",
                  },
                  {
                    mountPath = "/var/loki",
                    name = "data",
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
            # TODO: transformer that does volumeFromConfigMap and gives you path an object
            volumes = [
              { emptyDir = {}, name = "tmp", },
              { emptyDir = {}, name = "data", },
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
    loki-read-headless-service = t.HeadlessServiceForWorkload loki-read-deployment,
    loki-read-poddisruptionbudget = t.PodDisruptionBudgetForWorkload loki-read-deployment ('maxUnavailable 1),
    loki-read-service = t.ServiceFromDeployment loki-read-deployment,
  }
