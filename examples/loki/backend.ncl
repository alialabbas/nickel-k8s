let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "backend",
    _labels = utils.common_labels version "backend",
  in
  {
    loki-backend-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _selectors,
        name = "loki-backend",
      },
      spec = {
        persistentVolumeClaimRetentionPolicy = { whenDeleted = "Delete", whenScaled = "Delete", },
        podManagementPolicy = "Parallel",
        replicas = 3,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = _selectors,
        },
        serviceName = loki-backend-headless-service.metadata.name,
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
                        "app.kubernetes.io/component" = "backend",
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
                env = [
                  {
                    name = "METHOD",
                    value = "WATCH",
                  },
                  {
                    name = "LABEL",
                    value = "loki_rule",
                  },
                  {
                    name = "FOLDER",
                    value = "/rules",
                  },
                  {
                    name = "RESOURCE",
                    value = "both",
                  },
                  {
                    name = "WATCH_SERVER_TIMEOUT",
                    value = "60",
                  },
                  {
                    name = "WATCH_CLIENT_TIMEOUT",
                    value = "60",
                  },
                  {
                    name = "LOG_LEVEL",
                    value = "INFO",
                  }
                ],
                # TODO: this sidecar can be optional in the inputs
                image = "kiwigrid/k8s-sidecar:1.28.0",
                imagePullPolicy = "IfNotPresent",
                name = "loki-sc-rules",
                volumeMounts = [
                  {
                    mountPath = "/rules",
                    name = "sc-rules-volume",
                  }
                ],
              },
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=backend",
                  "-legacy-read-mode=false"
                ],
                image = "docker.io/grafana/loki:3.3.2",
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
                  },
                  {
                    mountPath = "/rules",
                    name = "sc-rules-volume",
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
            terminationGracePeriodSeconds = 300,
            volumes = [
              { emptyDir = {}, name = "tmp", },
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
              },
              {
                emptyDir = {},
                name = "sc-rules-volume",
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
    loki-backend-headless-service = t.HeadlessServiceForWorkload loki-backend-statefulset,
    loki-backend-poddisruptionbudget = t.PodDisruptionBudgetForWorkload loki-backend-statefulset ('maxUnavailable 1),
    loki-backend-service = t.ServiceFromDeployment loki-backend-statefulset,
  }
