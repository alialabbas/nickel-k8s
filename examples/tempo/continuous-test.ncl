let f | String -> String -> String -> { .. } = fun version write_endpoint read_endpoint =>
  let
    _labels = {
      "app.kubernetes.io/instance" = "tempo",
      "app.kubernetes.io/name" | force = "tempo",
      "app.kubernetes.io/version" = version,
      "app.kubernetes.io/component" = "tempo-vulture",
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
    tempo-vulture-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _labels,
        name = "tempo-vulture",
      },
      spec = {
        minReadySeconds = 10,
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = labels_to_selectors metadata.labels,
        },
        template = {
          metadata = {
            labels = tempo-vulture-deployment.metadata.labels,
          },
          spec = {
            containers = [
              {
                args = [
                  "-prometheus-listen-address=:8080",
                  "-tempo-push-url=http://%{write_endpoint}",
                  "-tempo-query-url=http://%{read_endpoint}"
                ],
                image = "docker.io/grafana/tempo-vulture:%{version}",
                imagePullPolicy = "IfNotPresent",
                name = "tempo-vulture",
                ports = [
                  {
                    containerPort = 8080,
                    name = "prom-metrics",
                  }
                ],
                resources = { requests = { cpu = "0.1", memory = "200Mi" } },
              }
            ],
            serviceAccountName = tempo-vulture-serviceaccount.metadata.name,
          },
        },
      },
    },
    tempo-vulture-serviceaccount = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = "tempo-vulture",
      },
    },
  }
in
f
