let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
# All of these need the target name
# All of these need version
# Function to load this or something else, what matters it has to overridable
# Typed or better contracted with semver or something
fun version =>
  let
    _selectors = utils.component_selectors "canary",
    _labels = utils.common_labels version "canary",
  in
  {
    loki-canary-daemonset = {
      apiVersion = "apps/v1",
      kind = "DaemonSet",
      metadata = {
        labels = _labels,
        name = "loki-canary",
      },
      spec = {
        selector = {
          matchLabels = _selectors,
        },
        template = {
          metadata = {
            labels = _labels
          },
          spec = {
            containers = [
              {
                args = [
                  "-addr=release-name-loki-gateway.default.svc.cluster.local.:80",
                  "-labelname=pod",
                  "-labelvalue=$(POD_NAME)",
                  "-user=self-monitoring",
                  "-tenant-id=self-monitoring",
                  "-pass=",
                  "-push=true"
                ],
                env = [
                  {
                    name = "POD_NAME",
                    valueFrom = {
                      fieldRef = {
                        fieldPath = "metadata.name",
                      },
                    },
                  }
                ],
                image = "docker.io/grafana/loki-canary:3.3.2",
                imagePullPolicy = "IfNotPresent",
                name = "loki-canary",
                ports = [
                  {
                    containerPort = 3500,
                    name = "http-metrics",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = {
                    path = "/metrics",
                    port = "http-metrics",
                  },
                  initialDelaySeconds = 15,
                  timeoutSeconds = 1,
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
              }
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = "loki-canary",
          },
        },
        updateStrategy = {
          rollingUpdate = { maxUnavailable = 1, },
          type = "RollingUpdate",
        },
      },
    },
    loki-canary-service = t.ServiceFromDeployment loki-canary-daemonset,
    loki-canary-serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = true,
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = "loki-canary",
      },
    }
  }
