let selectors = {
  "app.kubernetes.io/instance" = "grafana",
  "app.kubernetes.io/name" = "grafana",
}
in
let gen_label = fun version =>
  selectors
  & {
    "app.kubernetes.io/version" = version,
  }
in
let schema = {
  version | String | default = "12.1.0",
  # DataSources? How do we augment them?
  # Each object has its own schema, having a unified schema will be impossible without grafana-sdks stuff
  # Gosh even the sdk sucks in this regard, for now feed the list of datasources as an option
  # Where do these datasources lives and how to control them
  # We just want an easy way to bootstrap them based on what module is loaded really.
  # Like if loki is loaded, we add the datasource for it and so on
  # Yeah if this is an override we will never be able to capture the url correct
  datasources | Array { .. } | default = [],
}
in
{
  inputs | schema | default = {},
  release_metadata = {},
  manifests = {
    clusterrole = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRole",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      rules = [],
    },
    clusterrolebinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRoleBinding",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io",
        kind = "ClusterRole",
        name = clusterrole.metadata.name,
      },
      subjects = [
        {
          kind = "ServiceAccount",
          name = serviceaccount.metadata.name,
          namespace = release_metadata.namespace,
        }
      ],
    },
    configmap = {
      apiVersion = "v1",
      data = {
        # TODO: ini parser, perfect world would be to parse this and make it accessible through a record and vice versa
        "grafana.ini" = (import "grafana.ini" as 'Text),
        # TODO: this might need a separate configmap depending on its size
        "datasources.yaml" =
          std.serialize
            'Yaml
            ({
              apiVersion = 1,
              datasources = inputs.datasources,
            }
            ),
      },
      kind = "ConfigMap",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
    },
    deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
        namespace = "monitoring",
      },
      spec = {
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = selectors,
        },
        strategy = { type = "RollingUpdate", },
        template = {
          metadata = {
            annotations = {
              "kubectl.kubernetes.io/default-container" = "grafana",
            },
            labels = deployment.metadata.labels,
          },
          spec = {
            automountServiceAccountToken = true,
            containers = [
              {
                resources = { requests = { cpu = "1", memory = "1Gi", } },
                env = [
                  {
                    name = "POD_IP",
                    valueFrom = {
                      fieldRef = {
                        fieldPath = "status.podIP",
                      },
                    },
                  },
                  # TODO: Perfect world would have these parsed based on an ini schema
                  {
                    name = "GF_SECURITY_ADMIN_USER",
                    valueFrom = {
                      secretKeyRef = {
                        key = "admin-user",
                        # TODO: this is not recursive once we start manipulating the data form
                        name = secret.metadata.name,
                      },
                    },
                  },
                  {
                    name = "GF_SECURITY_ADMIN_PASSWORD",
                    valueFrom = {
                      secretKeyRef = {
                        key = "admin-password",
                        name = secret.metadata.name,
                      },
                    },
                  },
                  {
                    name = "GF_PATHS_DATA",
                    value = "/var/lib/grafana/",
                  },
                  {
                    name = "GF_PATHS_LOGS",
                    value = "/var/log/grafana",
                  },
                  {
                    name = "GF_PATHS_PLUGINS",
                    value = "/var/lib/grafana/plugins",
                  },
                  {
                    name = "GF_PATHS_PROVISIONING",
                    value = "/etc/grafana/provisioning",
                  }
                ],
                image = "docker.io/grafana/grafana:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  failureThreshold = 10,
                  httpGet = {
                    path = "/api/health",
                    port = 3000,
                  },
                  initialDelaySeconds = 60,
                  timeoutSeconds = 30,
                },
                name = "grafana",
                ports = [
                  {
                    containerPort = 3000,
                    name = "grafana",
                    protocol = "TCP",
                  },
                  {
                    containerPort = 9094,
                    name = "gossip-tcp",
                    protocol = "TCP",
                  },
                  # TODO: bug here with merging, we need to make a unique combined key from containerPort/protocol and then read it back
                  # {
                  #   containerPort = 9094,
                  #   name = "gossip-udp",
                  #   protocol = "UDP",
                  # }
                ],
                readinessProbe = {
                  httpGet = {
                    path = "/api/health",
                    port = 3000,
                  },
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  seccompProfile = { type = "RuntimeDefault", },
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/grafana/grafana.ini",
                    name = "config",
                    subPath = "grafana.ini",
                  },
                  {
                    mountPath = "/var/lib/grafana",
                    name = "storage",
                  },
                  {
                    name = "config",
                    mountPath = "/etc/grafana/provisioning/datasources/datasources.yaml",
                    subPath = "datasources.yaml",
                  }
                ],
              }
            ],
            enableServiceLinks = true,
            securityContext = {
              fsGroup = 472,
              runAsGroup = 472,
              runAsNonRoot = true,
              runAsUser = 472,
            },
            serviceAccountName = serviceaccount.metadata.name,
            volumes = [
              {
                configMap = { name = configmap.metadata.name, },
                name = "config",
              },
              { emptyDir = {}, name = "storage", }
            ],
          },
        },
      },
    },
    role = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "Role",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      rules = [],
    },
    rolebinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "RoleBinding",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io",
        kind = "Role",
        name = role.metadata.name,
      },
      subjects = [
        {
          kind = "ServiceAccount",
          name = serviceaccount.metadata.name,
          namespace = release_metadata.namespace,
        }
      ],
    },
    secret = {
      apiVersion = "v1",
      data = {
        admin-password = "OHF4bXYyWk5zQ1BLMlJobjB4V2FGZnlTdUNtRDNuVjlXckJZTm54SQ==",
        admin-user = "YWRtaW4=",
        ldap-toml = "",
      },
      kind = "Secret",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      type = "Opaque",
    },
    service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
      spec = {
        ports = [
          {
            name = "service",
            port = 80,
            protocol = "TCP",
            targetPort = 3000,
          }
        ],
        selector = selectors,
        type = "ClusterIP",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = false,
      kind = "ServiceAccount",
      metadata = {
        labels = gen_label inputs.version,
        name = "grafana",
      },
    },
  },
} | (import "../kube.ncl").Release
