let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "memcached-chunks-cache",
    _labels = utils.common_labels version "memcached-chunks-cache",
  in
  # TODO: would be great if this a realease on its own, hey here is how to deploy a memcache and here is what else you configure from it
  # BONUS: get the DNS from here into the config or the other way around
  # The biggest challenge is really how to configure the prefixes for one and the other while keeping the concept of a memcache release hidden away
  # Of course a simple util can be written to closurize the Package as if nothing happened while applying what we want. Become internal to the module only
  {
    chunks-cache-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels,
        name = "chunks-cache",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 1,
        selector = {
          matchLabels = _selectors,
        },
        serviceName = "chunks-cache",
        template = {
          metadata = {
            labels = _labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-m 8192",
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
                  limits = { memory = "9830Mi", },
                  requests = {
                    cpu = "500m",
                    memory = "9830Mi",
                  },
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
              },
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
    chunks-cache-service = t.HeadlessServiceForWorkload chunks-cache-statefulset,
    chunks-cache-pdb = t.PodDisruptionBudgetForWorkload chunks-cache-statefulset ('maxUnavailable 1)
  }
