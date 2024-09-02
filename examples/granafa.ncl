let selectors = {
  "app.kubernetes.io/instance" = "grafana",
  "app.kubernetes.io/name" = "grafana",
}
in
{
  Manifests = {
    grafana-clusterrole = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRole",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
        },
        name = "grafana",
      },
      rules = [],
    },
    grafana-clusterrolebinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRoleBinding",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
      },
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io",
        kind = "ClusterRole",
        name = "grafana",
      },
      subjects = [
        {
          kind = "ServiceAccount",
          name = "grafana",
          namespace = "monitoring",
        }
      ],
    },
    grafana-configmap = {
      apiVersion = "v1",
      data = {
        "grafana.ini" = "[analytics]\ncheck_for_updates = true\n[grafana_net]\nurl = https://grafana.net\n[log]\nmode = console\n[paths]\ndata = /var/lib/grafana/\nlogs = /var/log/grafana\nplugins = /var/lib/grafana/plugins\nprovisioning = /etc/grafana/provisioning\n[server]\ndomain = ''\n",
      },
      kind = "ConfigMap",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
      },
    },
    grafana-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = {
          "app.kubernetes.io/version" = "10.4.1",
        } & selectors,
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
            labels = grafana-deployment.metadata.labels,
          },
          spec = {
            automountServiceAccountToken = true,
            containers = [
              {
                env = [
                  {
                    name = "POD_IP",
                    valueFrom = {
                      fieldRef = {
                        fieldPath = "status.podIP",
                      },
                    },
                  },
                  {
                    name = "GF_SECURITY_ADMIN_USER",
                    valueFrom = {
                      secretKeyRef = {
                        key = "admin-user",
                        name = "grafana",
                      },
                    },
                  },
                  {
                    name = "GF_SECURITY_ADMIN_PASSWORD",
                    valueFrom = {
                      secretKeyRef = {
                        key = "admin-password",
                        name = "grafana",
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
                image = "docker.io/grafana/grafana:10.4.1",
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
                  {
                    containerPort = 9094,
                    name = "gossip-udp",
                    protocol = "UDP",
                  }
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
            serviceAccountName = "grafana",
            volumes = [
              {
                configMap = { name = "grafana", },
                name = "config",
              },
              { emptyDir = {}, name = "storage", }
            ],
          },
        },
      },
    },
    grafana-role = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "Role",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
      },
      rules = [],
    },
    grafana-rolebinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "RoleBinding",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
      },
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io",
        kind = "Role",
        name = "grafana",
      },
      subjects = [
        {
          kind = "ServiceAccount",
          name = "grafana",
          namespace = "default",
        }
      ],
    },
    grafana-secret = {
      apiVersion = "v1",
      data = {
        admin-password = "OHF4bXYyWk5zQ1BLMlJobjB4V2FGZnlTdUNtRDNuVjlXckJZTm54SQ==",
        admin-user = "YWRtaW4=",
        ldap-toml = "",
      },
      kind = "Secret",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
      },
      type = "Opaque",
    },
    grafana-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
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
        selector = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/name" = "grafana",
        },
        type = "ClusterIP",
      },
    },
    grafana-serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = false,
      kind = "ServiceAccount",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "grafana",
          "app.kubernetes.io/managed-by" = "Helm",
          "app.kubernetes.io/name" = "grafana",
          "app.kubernetes.io/version" = "10.4.1",
          "helm.sh/chart" = "grafana-7.3.11",
        },
        name = "grafana",
        namespace = "default",
      },
    },
  },
} | (import "../kube.ncl").Release
