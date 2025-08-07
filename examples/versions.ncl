let p = import "../policies.ncl" in
{
  mimir = {
    release_metadata = {
      prefix = "lgtm-",
      labels = {
        "app.kubernetes.io/instance" | force = "lgtm-mimir",
      }
    },
    inputs = {
      mode = 'distributed,
      config.blocks_storage = {
        backend | force = "s3",
        s3 = {
          access_key_id = "grafana-mimir",
          bucket_name = "mimir-tsdb",
          endpoint = "minio:9000",
          insecure = true,
          secret_access_key = "supersecret",
        },
      }
    },
    output = { endpoints, },
  },

  loki = {
    # Should this be encouraged when it is necessary
    # In some cases it is really important to do this
    # This would be the only way for something like this replication factor to be captured in a senseible logic
    # of course the downside is, the user has to know how these resources are named but that's not complex
    # manifests.ingester-statefulset.spec.replicas | force = 3,

    release_metadata = {
      prefix = "lgtm-",
      labels = {
        "app.kubernetes.io/instance" | force = "testing",
      }
    },
    inputs = {
      mode = 'single-binary,
      config = {
        ui.enabled = true,
        ruler.storage.s3.bucketnames = "loki-ruler",
        common.storage.s3 = {
          access_key_id = "grafana-mimir",
          bucketnames = "loki-chunks",
          endpoint = "minio:9000",
          insecure = true,
          s3forcepathstyle = true,
          secret_access_key = "supersecret",
        },
        limits_config.allow_structured_metadata = true,
      }
    },
    output = { endpoints, },
  },

  tempo = {
    release_metadata = {
      prefix = "lgtm-",
      labels = {
        "app.kubernetes.io/instance" | force = "testing",
      }
    },
    inputs = {
      mode = 'distributed,
      config = {
        storage.trace = {
          backend | force = "s3",
          s3 = {
            bucket = "tempo-traces",
            endpoint = "minio:9000",
            access_key = "grafana-mimir",
            secret_key = "supersecret",
            insecure = true,
          },
        },
      },
    },
    output = { endpoints, },
  },

  pyroscope = {
    release_metadata = {
      prefix = "lgtm-",
      labels = {
        "app.kubernetes.io/instance" | force = "lgtm-pyroscope",
        "app.custom.label" = "testing",
      }
    },
    output = { endpoints, },
    inputs = {
      mode = 'distributed,
      config = {
        storage = {
          backend = "s3",
          s3 = {
            access_key_id = "grafana-mimir",
            bucket_name = "grafana-pyroscope-data",
            endpoint = "minio:9000",
            insecure = true,
            secret_access_key = "supersecret",
          }
        }
      }
    }
  },

  opentelemetry-collector = {
    inputs.config = {
      receivers.otlp.protocols.http.endpoint | force = "0.0.0.0:4318",
      exporters = {
        "otlphttp/loki" = {
          endpoint = "http://" ++ loki.output.endpoints.writer ++ "/otlp",
          tls = {
            insecure = true
          }
        },
        "otlphttp/mimir" = {
          endpoint = "http://" ++ mimir.output.endpoints.writer ++ "/otlp",
          tls = {
            insecure = true
          }
        },
        "otlp/tempo" = {
          endpoint = tempo.output.endpoints.otlp,
          tls = {
            insecure = true
          },
        }
      },
      service.pipelines = {
        logs.exporters | force = ["otlphttp/loki", "debug", ],
        metrics.exporters | force = ["otlphttp/mimir", "debug", ],
        traces.exporters | force = ["otlp/tempo", "debug", ],
      }
    },
    overlays = [
      {
        apiVersion = "apps/v1",
        kind = "Deployment",
        metadata = { name = "opentelemetry-collector" },
        spec = {
          template.spec.containers = [
            {
              name = "opentelemetry-collector",
              resources = {
                limits = {
                  cpu = 1,
                  memory = "20Gi",
                },
              },
            },
          ]
        }
      },
    ]
  },

  grafana = {
    inputs = {
      datasources = [
        {
          name = "Loki",
          type = "loki",
          access = "proxy",
          url = "http://" ++ loki.output.endpoints.reader
        },
        {
          name = "Mimir",
          type = "prometheus",
          url = "http://" ++ mimir.output.endpoints.reader ++ "/prometheus"
        },
        {
          name = "Tempo",
          type = "tempo",
          url = "http://" ++ tempo.output.endpoints.reader,
        },
        {
          name = "Pyroscope",
          type = "grafana-pyroscope-datasource",
          url = "http://" ++ pyroscope.output.endpoints.reader,
        },
      ],
    },
  },

  minio = {
    inputs = {
      buckets = [
        {
          name = "grafana-pyroscope-data",
          policy = "none",
          purge = false,
          versioned = false,
          locking = false,
        },
        {
          name = "tempo-traces",
          policy = "none",
          purge = false,
          versioned = false,
          locking = false,
        },
        {
          name = "mimir-tsdb",
          policy = "none",
          purge = false,
          versioned = false,
          locking = false,
        },
        {
          name = "loki-chunks",
          policy = "none",
          purge = false,
          versioned = false,
          locking = false,
        },
        {
          name = "loki-ruler",
          policy = "none",
          purge = false,
          versioned = false,
          locking = false,
        },
      ]
    },
  },
}
