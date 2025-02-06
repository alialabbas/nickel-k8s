let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "memcached-results-cache",
    _labels = utils.common_labels version "memcached-results-cache",
  in
  {
    results-cache-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        annotations = {},
        labels = _labels,
        name = "results-cache",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 1,
        selector = {
          matchLabels = _selectors,
        },
        serviceName = "results-cache",
        template = {
          metadata = {
            labels = _labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-m 1024",
                  "--extended=modern,track_sizes",
                  "-I 5m",
                  "-c 16384",
                  "-v",
                  "-u 11211"
                ],
                image = "memcached:1.6.33-alpine",
                imagePullPolicy = "IfNotPresent",
                name = "memcached",
                ports = [
                  {
                    containerPort = 11211,
                    name = "client",
                  }
                ],
                resources = {
                  limits = { memory = "1229Mi", },
                  requests = {
                    cpu = "500m",
                    memory = "1229Mi",
                  },
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
              },
              # TODO: exporter should be a feature or better an overlay
              {
                args = [
                  "--memcached.address=localhost:11211",
                  "--web.listen-address=0.0.0.0:9150"
                ],
                image = "prom/memcached-exporter:v0.15.0",
                imagePullPolicy = "IfNotPresent",
                name = "exporter",
                ports = [
                  {
                    containerPort = 9150,
                    name = "http-metrics",
                  }
                ],
                resources = { limits = {}, requests = {}, },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
              }
            ],
            securityContext = {
              fsGroup = 11211,
              runAsGroup = 11211,
              runAsNonRoot = true,
              runAsUser = 11211,
            },
            serviceAccountName = "loki",
            terminationGracePeriodSeconds = 60,
          },
        },
        updateStrategy = { type = "RollingUpdate", },
      },
    },
    results-cache-service = t.HeadlessServiceForWorkload results-cache-statefulset,
    results-cache-pdb = t.PodDisruptionBudgetForWorkload results-cache-statefulset ('maxUnavailable 1)
  }
