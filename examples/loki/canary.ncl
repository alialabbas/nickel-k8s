let t = import "../../transfomers.ncl" in
fun version loki_address =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "loki",
      "app.kubernetes.io/name" | force = "loki",
      "app.kubernetes.io/version" = version,
      "app.kubernetes.io/component" | force = "loki-canary"
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
    loki-canary-daemonset = {
      apiVersion = "apps/v1",
      kind = "DaemonSet",
      metadata = {
        labels = _labels,
        name = "loki-canary",
      },
      spec = {
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        template = {
          metadata = {
            labels = loki-canary-daemonset.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-addr=%{loki_address}",
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
                image = "docker.io/grafana/loki-canary:%{version}",
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
            serviceAccountName = loki-canary-serviceaccount.metadata.name,
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
