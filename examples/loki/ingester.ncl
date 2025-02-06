let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
  # TODO: optional flag for generating either a zone aware replication or not
  # TODO: limit to these what what we typically will want to create for zones
  _zone = fun zone =>
    {
      name = "ingester-zone-%{std.to_string zone}",
      rollout-group = "ingester",
    },
  _selectors = utils.component_selectors "ingester",
  _labels = utils.common_labels version "ingester",
  _pod_template = utils.pod_template version "ingester",
  in
  let zones = ["a", "b", "c"] in
  let ingesters =
    std.array.fold_left
      (fun acc e =>
        acc
        & {
          "ingester-zone-%{e}-headless-service" = {
            apiVersion = "v1",
            kind = "Service",
            metadata = {
              labels = _labels,
              name = "ingester-zone-%{e}-headless",
            },
            spec = {
              clusterIP = "None",
              ports = [
                {
                  name = "http-metrics",
                  port = 3100,
                  protocol = "TCP",
                  targetPort = "http-metrics",
                },
                {
                  name = "grpc",
                  port = 9095,
                  protocol = "TCP",
                  targetPort = "grpc",
                }
              ],
              selector = _selectors & (_zone e),
            },
          },
          "ingester-zone-%{e}-statefulset" = {
            apiVersion = "apps/v1",
            kind = "StatefulSet",
            metadata = {
              annotations = { rollout-max-unavailable = "1", },
              labels = _labels & _zone e,
              name = "ingester-zone-%{e}",
            },
            spec = {
              podManagementPolicy = "Parallel",
              replicas = 1,
              revisionHistoryLimit = 10,
              selector = {
                matchLabels = _selectors & (_zone e),
              },
              serviceName = "ingester-zone-%{e}",
              template = {
                metadata = {
                  labels = _selectors & (_zone e),
                },
                spec = {
                  affinity = {
                    podAntiAffinity = {
                      requiredDuringSchedulingIgnoredDuringExecution = [
                        {
                          labelSelector = {
                            matchExpressions = [
                              {
                                key = "rollout-group",
                                operator = "In",
                                values = [
                                  "ingester"
                                ],
                              },
                              {
                                key = "name",
                                operator = "NotIn",
                                values = [
                                  "ingester-zone-%{e}"
                                ],
                              }
                            ],
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
                        "-ingester.availability-zone=zone-%{e}",
                        "-ingester.unregister-on-shutdown=false",
                        "-ingester.tokens-file-path=/var/loki/ring-tokens",
                        "-target=ingester"
                      ],
                      image = "docker.io/grafana/loki:%{version}",
                      imagePullPolicy = "IfNotPresent",
                      name = "ingester",
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
                  terminationGracePeriodSeconds = 300,
                  topologySpreadConstraints = [
                    {
                      labelSelector = {
                        matchLabels = {
                          "app.kubernetes.io/component" = "ingester",
                        },
                      },
                      maxSkew = 1,
                      topologyKey = "kubernetes.io/hostname",
                      whenUnsatisfiable = "ScheduleAnyway",
                    }
                  ],
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
                    },
                    { emptyDir = {}, name = "data", }
                  ],
                },
              },
              updateStrategy = { type = "RollingUpdate", },
            },
          },
        }
      )
      {}
      zones
  in
  {
    ingester-rollout-poddisruptionbudget = {
      apiVersion = "policy/v1",
      kind = "PodDisruptionBudget",
      metadata = {
        labels = _labels,
        name = "ingester-rollout",
      },
      spec = {
        maxUnavailable = 1,
        selector = { matchLabels = { rollout-group = "ingester", }, },
      },
    },
  }
  & ingesters
