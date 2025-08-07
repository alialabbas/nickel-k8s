let selectors : { _ : String } = {
  "app.kubernetes.io/instance" = "minio",
  "app.kubernetes.io/name" = "minio",
}
in
let common_labels
  : String -> { _ : String }
  = fun version =>
    selectors
    |> std.record.update "app.kubernetes.io/version" version,
in
{
  inputs
    | {
      version
        | String
        | default
        = "RELEASE.2024-12-18T13-15-44Z",
      buckets
        | doc "Buckets to create as part of minio bootstrap"
        | Array {
          name | String,
          policy | String,
          purge | Bool,
          versioned | Bool,
          locking | Bool,
        }
        | default
        = [],

      users | Array String,
    }
    = {},

  manifests =
    let
      _labels = common_labels inputs.version,
      _api_port = 9000,
      _console_port = 9001
    in
    {
      configmap = {
        apiVersion = "v1",
        data = {
          add-policy = import "./minio/add-policy" as 'Text,
          add-svcacct = import "./minio/add-svcacct" as 'Text,
          add-user = import "./minio/add-user" as 'Text,
          custom-command = import "./minio/custom-command" as 'Text,
          initialize =
            (import "./minio/initialize" as 'Text)
            ++ (std.array.fold_right (fun e acc => acc ++ "\ncreateBucket %{e.name} %{e.policy} %{e.purge} %{e.versioned} %{e.locking}") "" inputs.buckets),
        },
        kind = "ConfigMap",
        metadata = {
          labels = _labels,
          name = "minio",
        },
      },
      console-service = {
        apiVersion = "v1",
        kind = "Service",
        metadata = {
          labels = _labels,
          name = "minio-console",
        },
        spec = {
          ports = [
            {
              name = "http",
              port = _console_port,
              protocol = "TCP",
              targetPort = _console_port,
            }
          ],
          selector = selectors,
          type = "ClusterIP",
        },
      },
      deployment = {
        apiVersion = "apps/v1",
        kind = "Deployment",
        metadata = {
          labels = _labels,
          name = "minio",
        },
        spec = {
          replicas = 1,
          selector = { matchLabels = _labels, },
          strategy = {
            rollingUpdate = { maxSurge = "100%", maxUnavailable = 0, },
            type = "RollingUpdate",
          },
          template = {
            metadata = {
              labels = _labels,
              name = "minio",
            },
            spec = {
              containers = [
                {
                  command = [
                    "/bin/sh",
                    "-ce",
                    "/usr/bin/docker-entrypoint.sh minio server /export -S /etc/minio/certs/ --address :9000 --console-address :9001"
                  ],
                  env = [
                    {
                      name = "MINIO_ROOT_USER",
                      valueFrom = {
                        secretKeyRef = {
                          key = "rootUser",
                          name = secret.metadata.name,
                        },
                      },
                    },
                    {
                      name = "MINIO_ROOT_PASSWORD",
                      valueFrom = {
                        secretKeyRef = {
                          key = "rootPassword",
                          name = secret.metadata.name,
                        },
                      },
                    },
                    {
                      name = "MINIO_PROMETHEUS_AUTH_TYPE",
                      value = "public",
                    }
                  ],
                  image = "quay.io/minio/minio:%{inputs.version}",
                  imagePullPolicy = "IfNotPresent",
                  name = "minio",
                  ports = [
                    {
                      containerPort = _api_port,
                      name = "http",
                    },
                    {
                      containerPort = _console_port,
                      name = "http-console",
                    }
                  ],
                  resources = {
                    requests = {
                      cpu = "100m",
                      memory = "128Mi",
                    },
                  },
                  volumeMounts = [
                    {
                      mountPath = "/tmp/credentials",
                      name = "minio-user",
                      readOnly = true,
                    },
                    {
                      mountPath = "/export",
                      name = "export",
                    }
                  ],
                }
              ],
              serviceAccountName = serviceaccount.metadata.name,
              volumes = [
                { emptyDir = {}, name = "export", },
                {
                  name = "minio-user",
                  secret = { secretName = "minio", },
                }
              ],
            },
          },
        },
      },
      post-job = {
        apiVersion = "batch/v1",
        kind = "Job",
        metadata = {
          labels = _labels,
          name = "minio-post-job",
        },
        spec = {
          template = {
            metadata = {
              labels = _labels,
            },
            spec = {
              containers = [
                {
                  command = ["/bin/sh", "/config/initialize"],
                  env = [
                    {
                      name = "MINIO_ENDPOINT",
                      value = "minio",
                    },
                    {
                      name = "MINIO_PORT",
                      value = "9000",
                    }
                  ],
                  image = "quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z",
                  imagePullPolicy = "IfNotPresent",
                  name = "minio-make-bucket",
                  resources = { requests = { memory = "128Mi", }, },
                  volumeMounts = [
                    {
                      mountPath = "/etc/minio/mc",
                      name = "etc-path",
                    },
                    {
                      mountPath = "/tmp",
                      name = "tmp",
                    },
                    {
                      mountPath = "/config",
                      name = "minio-configuration",
                    }
                  ],
                },
                {
                  command = ["/bin/sh", "/config/add-user"],
                  env = [
                    {
                      name = "MINIO_ENDPOINT",
                      value = service.metadata.name,
                    },
                    {
                      name = "MINIO_PORT",
                      value = "9000",
                    }
                  ],
                  image = "quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z",
                  imagePullPolicy = "IfNotPresent",
                  name = "minio-make-user",
                  resources = { requests = { memory = "128Mi", }, },
                  volumeMounts = [
                    {
                      mountPath = "/etc/minio/mc",
                      name = "etc-path",
                    },
                    {
                      mountPath = "/tmp",
                      name = "tmp",
                    },
                    {
                      mountPath = "/config",
                      name = "minio-configuration",
                    }
                  ],
                }
              ],
              restartPolicy = "OnFailure",
              serviceAccountName = serviceaccount.metadata.name,
              volumes = [
                { emptyDir = {}, name = "etc-path", },
                { emptyDir = {}, name = "tmp", },
                {
                  name = "minio-configuration",
                  projected = {
                    sources = [
                      {
                        configMap = { name = configmap.metadata.name, },
                      },
                      {
                        secret = { name = manifests.secret.metadata.name, },
                      }
                    ],
                  },
                }
              ],
            },
          },
        },
      },
      serviceaccount = {
        apiVersion = "v1",
        kind = "ServiceAccount",
        metadata = { name = "minio", labels = _labels },
      },
      secret = {
        apiVersion = "v1",
        data = {
          rootPassword = "c3VwZXJzZWNyZXQ=",
          rootUser = "Z3JhZmFuYS1taW1pcg==",
        },
        kind = "Secret",
        metadata = {
          labels = _labels,
          name = "minio",
        },
        type = "Opaque",
      },
      service = {
        apiVersion = "v1",
        kind = "Service",
        metadata = {
          labels = _labels,
          name = "minio",
        },
        spec = {
          ports = [
            {
              name = "http",
              port = _api_port,
              protocol = "TCP",
              targetPort = _api_port,
            }
          ],
          selector = selectors,
          type = "ClusterIP",
        },
      },
    },
}
