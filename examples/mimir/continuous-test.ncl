fun inputs read_endpoint write_endpoint =>
  let labels_to_selectors = fun labels =>
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
    continuous-test-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = {
          "app.kubernetes.io/instance" = "mimir",
          "app.kubernetes.io/name" | force = "mimir",
          "app.kubernetes.io/version" = inputs.version,
          "app.kubernetes.io/component" = "test",
        },
        name = "mimir-continuous-test",
      },
      spec = {
        replicas = 1,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
          type = "RollingUpdate",
        },
        template = {
          metadata = {
            labels = continuous-test-deployment.metadata.labels,
          },
          # TODO: this need to add the args later on
          spec = {
            containers = [
              {
                args = [
                  "-activity-tracker.filepath=",
                  # "-tests.smoke-test",
                  "-tests.write-endpoint=http://%{write_endpoint}",
                  "-tests.read-endpoint=http://%{read_endpoint}/prometheus",
                  "-tests.tenant-id=anonymous",
                  "-tests.write-read-series-test.num-series=1000",
                  "-tests.write-read-series-test.max-query-age=48h",
                  # "-server.metrics-port=8080",
                ],
                image = "docker.io/grafana/mimir-continuous-test:%{inputs.version}",
                imagePullPolicy = "IfNotPresent",
                livenessProbe = {
                  httpGet = { path = "/ready", port = "http", },
                  initialDelaySeconds = 300,
                },
                # TODO: Has port and can expose its metrics
                name = "mimir-test",
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
              }
            ],
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            terminationGracePeriodSeconds = 30,
          },
        },
      },
    },
  }
