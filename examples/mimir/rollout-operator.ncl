{
  rollout-operator-deployment = {
    apiVersion = "apps/v1",
    kind = "Deployment",
    metadata = {
      labels = {
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "rollout-operator",
        "app.kubernetes.io/version" = "v0.13.0",
        "helm.sh/chart" = "rollout-operator-0.14.0",
      },
      name = "mimir-distributed-rollout-operator",
    },
    spec = {
      minReadySeconds = 10,
      replicas = 1,
      selector = {
        matchLabels = {
          "app.kubernetes.io/instance" = "mimir-distributed",
          "app.kubernetes.io/name" = "rollout-operator",
        },
      },
      strategy = {
        rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
      },
      template = {
        metadata = {
          labels = {
            "app.kubernetes.io/instance" = "mimir-distributed",
            "app.kubernetes.io/name" = "rollout-operator",
          },
        },
        spec = {
          containers = [
            {
              args = ["-kubernetes.namespace=default"],
              image = "grafana/rollout-operator:v0.13.0",
              imagePullPolicy = "IfNotPresent",
              name = "rollout-operator",
              ports = [
                {
                  containerPort = 8001,
                  name = "http-metrics",
                  protocol = "TCP",
                }
              ],
              readinessProbe = {
                httpGet = {
                  path = "/ready",
                  port = "http-metrics",
                },
                initialDelaySeconds = 5,
                timeoutSeconds = 1,
              },
              resources = {
                limits = { memory = "200Mi", },
                requests = {
                  cpu = "100m",
                  memory = "100Mi",
                },
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
            seccompProfile = { type = "RuntimeDefault", },
          },
          serviceAccountName = "mimir-distributed-rollout-operator",
        },
      },
    },
  },
  rollout-operator-role = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "Role",
    metadata = { name = "mimir-distributed-rollout-operator", },
    rules = [
      {
        apiGroups = [""],
        resources = ["pods"],
        verbs = ["list", "get", "watch", "delete"],
      },
      {
        apiGroups = ["apps"],
        resources = ["statefulsets"],
        verbs = ["list", "get", "watch"],
      },
      {
        apiGroups = ["apps"],
        resources = ["statefulsets/status"],
        verbs = ["update"],
      }
    ],
  },
  rollout-operator-rolebinding = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "RoleBinding",
    metadata = { name = "mimir-distributed-rollout-operator", },
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io",
      kind = "Role",
      name = "mimir-distributed-rollout-operator",
    },
    subjects = [
      {
        kind = "ServiceAccount",
        name = "mimir-distributed-rollout-operator",
      }
    ],
  },
  rollout-operator-serviceaccount = {
    apiVersion = "v1",
    kind = "ServiceAccount",
    metadata = {
      labels = {
        "app.kubernetes.io/instance" = "mimir-distributed",
        "app.kubernetes.io/managed-by" = "Helm",
        "app.kubernetes.io/name" = "rollout-operator",
        "app.kubernetes.io/version" = "v0.13.0",
        "helm.sh/chart" = "rollout-operator-0.14.0",
      },
      name = "mimir-distributed-rollout-operator",
    },
  },
}
