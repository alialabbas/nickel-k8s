let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "ruler",
    _labels = utils.common_labels version "ruler",
    _podtemplate = utils.pod_template
  in
{
  ruler-statefulset = {
    apiVersion = "apps/v1",
    kind = "StatefulSet",
    metadata = {
      labels = _labels,
      name = "loki-ruler",
    },
    spec = {
      replicas = 0,
      revisionHistoryLimit = 10,
      selector = {
        matchLabels = _selectors,
      },
      serviceName = "loki-ruler",
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
                      "app.kubernetes.io/component" = "ruler",
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
                "-target=ruler"
              ],
              image = "docker.io/grafana/loki:3.3.2",
              imagePullPolicy = "IfNotPresent",
              name = "ruler",
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
                  mountPath = "/var/loki",
                  name = "data",
                },
                {
                  mountPath = "/tmp/loki",
                  name = "tmp",
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
            { emptyDir = {}, name = "tmp", },
            { emptyDir = {}, name = "data", }
          ],
        },
      },
    },
  },
  ruler-service = t.ServiceFromDeployment ruler-statefulset,
}
