# The question is how one would manage a complex deployment like this one where you just have so many pieces
# I guess what is not optional is slapped inside the core mimir-distributed with what is needed to run
# everything else is scattered around as optional pieces that are augmented by the user
{
  Manifests = {
    config = {
      apiVersion = "v1",
      data = {
        "mimir.yaml" = std.serialize 'Yaml (import "./mimir/config.yaml"),
      },
      kind = "ConfigMap",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/version" = "2.12.0",
        },
        name = "mimir-distributed-config",
        namespace = "monitoring",
      },
    },
    gossip-ring-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = {
          "app.kubernetes.io/component" = "gossip-ring",
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/version" = "2.12.0",

        },
        name = "mimir-distributed-gossip-ring",
        namespace = config.metadata.namespace,
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            appProtocol = "tcp",
            name = "gossip-ring",
            port = 7946,
            protocol = "TCP",
            targetPort = 7946,
          }
        ],
        publishNotReadyAddresses = true,
        selector = {
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/part-of" = "memberlist",
        },
        type = "ClusterIP",
      },
    },
    runtime-config= {
      apiVersion = "v1",
      data = {
        "runtime.yaml" = std.serialize 'Yaml ({} | (import "mimir/runtime-config.ncl")),
      },
      kind = "ConfigMap",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/version" = "2.12.0",
        },
        name = "mimir-distributed-runtime",
        namespace = config.metadata.namespace,
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        annotations = {},
        labels = {
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "mimir",
          "app.kubernetes.io/version" = "2.12.0",
        },
        name = "mimir-distributed",
        namespace = config.metadata.namespace,
      },
    },
  },
} | (import "../kube.ncl").Release
