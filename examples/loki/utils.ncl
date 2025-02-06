let loki_config = import "../loki.yaml" in
{
  pod_template
    | doc "This PodSpec define the most basic used in all loki deployments and statefulsets"
    # : String -> String -> Dyn
    = fun version component =>
      {
        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = component_selectors component
                  },
                  topologyKey = "failure-domain.beta.kubernetes.io/zone",
                },
                weight = 100,
              }
            ],
            requiredDuringSchedulingIgnoredDuringExecution = [
              {
                labelSelector = {
                  matchLabels = component_selectors component,
                },
                topologyKey = "kubernetes.io/hostname",
              }
            ],
          },
        },
        # Basically, since this is the top layer, we can override it ourselves when we need from args, ports and so on
        containers = [
          loki_container version component
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
            configMap = { name = "loki", },
            name = "config",
          },
          {
            configMap = { name = "loki-runtime", },
            name = "runtime-config",
          }
        ],
      },
  loki_container
  # : String -> String -> { _ : Dyn }
  = fun version component =>
    {
      args = [
        "-config.file=/etc/loki/config/config.yaml",
        "-target=%{component}"
      ],
      image = "docker.io/grafana/loki:%{version}",
      imagePullPolicy = "IfNotPresent",
      livenessProbe = {
        httpGet = { path = "/ready", port = "http", },
        initialDelaySeconds = 300,
      },
      name = component,
      ports = [
        {
          # TODO: the issue with this factorization is loading the config in multiple places.
          # unless this stupid somehow knows it is the same file and only load it once and reference it, TBD
          # Could always pass the config object here but it shouldn't a big factor unless the file is huge
          containerPort = loki_config.server.http_listen_port,
          name = "http",
          protocol = "TCP",
        },
        {
          containerPort = loki_config.server.grpc_listen_port,
          name = "grpc",
          protocol = "TCP",
        },
        {
          containerPort = loki_config.memberlist.advertise_port,
          name = "http-memberlist",
          protocol = "TCP",
        }
      ],
      readinessProbe = {
        httpGet = { path = "/ready", port = "http", },
        initialDelaySeconds = 30,
        timeoutSeconds = 1,
      },
      resources = {},
      securityContext = {
        allowPrivilegeEscalation = false,
        capabilities = { drop = ["ALL"], },
        readOnlyRootFilesystem = true,
      },
      # Basically this is how a merge form will look like and we will just write it this way
      # Another way is to just call the methods, really the same
      volumeMounts = [
        {
          mountPath = "/etc/loki/config",
          name = "config",
        },
        {
          mountPath = "/var/loki-runtime",
          name = "runtime-config",
        }
      ],
    },

  # TODO: if the import is done here directly, we could potentially just wrap this in mergable contract that enforces the Loki Schema without potentially polluting the underlying schema itself
  config = loki_config,

  # TODO: If there is a good contrac , we would be getting a correct value
  zone_aware = loki_config.ingester.lifecycler.ring.zone_awareness_enabled,
  # TODO: same thing, captured and non-modifable contract as much as possible
  runtime = {},
  # TODO: this need a contract based on Loki's component
  component_selectors : String -> { _ : String } = fun component =>
    {
      "app.kubernetes.io/component" = component,
      "app.kubernetes.io/instance" = "loki",
      "app.kubernetes.io/name" = "loki",
    },

  common_labels
    : String -> String -> { _ : String }
    = fun version component =>
      component_selectors component
      |> std.record.update "app.kubernetes.io/version" version,
}
