let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "write",
    _labels = utils.common_labels version "write",
  in
  {
    # TODO: need memberlist label management for deployments but not their respective services
    # TODO: ideally service shouldn't have the memberlist port if it is not the memberlist one
    loki-write-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels,
        name = "loki-write",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 3,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = _selectors,
        },
        serviceName = "loki-write-headless",
        template = {
          metadata = {
            labels = _labels,
          },
          spec = {
            affinity = {
              podAntiAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = [
                  {
                    labelSelector = {
                      matchLabels = {
                        "app.kubernetes.io/component" = "write",
                      },
                    },
                    topologyKey = "kubernetes.io/hostname",
                  }
                ],
              },
            },
            automountServiceAccountToken = true,
            containers = [
              {
                args = [
                  "-config.file=/etc/loki/config/config.yaml",
                  "-target=write"
                ],
                image = "docker.io/grafana/loki:%{version}",
                imagePullPolicy = "IfNotPresent",
                name = "loki",
                ports = [
                  {
                    containerPort = 3100,
                    name = "http-metrics",
                    protocol = "TCP",
                  },
                  {
                    containerPort = 9095,
                    name = "grpc",
                    protocol = "TCP",
                  },
                  {
                    containerPort = 7946,
                    name = "http-memberlist",
                    protocol = "TCP",
                  }
                ],
                readinessProbe = {
                  httpGet = {
                    path = "/ready",
                    port = "http-metrics",
                  },
                  initialDelaySeconds = 30,
                  timeoutSeconds = 1,
                },
                securityContext = {
                  allowPrivilegeEscalation = false,
                  capabilities = { drop = ["ALL"], },
                  readOnlyRootFilesystem = true,
                },
                volumeMounts = [
                  {
                    mountPath = "/etc/loki/config",
                    name = "config",
                  },
                  {
                    mountPath = "/etc/loki/runtime-config",
                    name = "runtime-config",
                  },
                  {
                    mountPath = "/var/loki",
                    name = "data",
                  }
                ],
              }
            ],
            enableServiceLinks = true,
            securityContext = {
              fsGroup = 10001,
              runAsGroup = 10001,
              runAsNonRoot = true,
              runAsUser = 10001,
            },
            serviceAccountName = "loki",
            terminationGracePeriodSeconds = 300,
            volumes = [
              {
                configMap = {
                  items = [
                    {
                      key = "config.yaml",
                      path = "config.yaml",
                    }
                  ],
                  name = "loki",
                },
                name = "config",
              },
              {
                configMap = { name = "loki-runtime", },
                name = "runtime-config",
              }
            ],
          },
        },
        updateStrategy = { rollingUpdate = { partition = 0, }, },
        volumeClaimTemplates = [
          {
            apiVersion = "v1",
            kind = "PersistentVolumeClaim",
            metadata = { name = "data", },
            spec = {
              accessModes = ["ReadWriteOnce"],
              resources = { requests = { storage = "10Gi", }, }, # TODO: this sizinig is a good contender for a module input
            },
          }
        ],
      },
    },
    loki-write-headless-service = t.ServiceFromDeployment loki-write-statefulset,
    loki-write-poddisruptionbudget = t.PodDisruptionBudgetForWorkload loki-write-statefulset ('maxUnavailable 1),
    loki-write-service = t.ServiceFromDeployment loki-write-statefulset,
    # Manifests =
    #   {
    #       loki-canary-daemonset =
    #         {
    #             apiVersion = "apps/v1",
    #             kind = "DaemonSet",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "canary",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-canary",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" = "canary",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                   template =
    #                     {
    #                         metadata =
    #                           {
    #                               labels =
    #                                 {
    #                                     "app.kubernetes.io/component" = "canary",
    #                                     "app.kubernetes.io/instance" =
    #                                       "release-name",
    #                                     "app.kubernetes.io/name" = "loki",
    #                                   },
    #                             },
    #                         spec =
    #                           {
    #                               containers =
    #                                 [
    #                                     {
    #                                       args =
    #                                         [
    #                                             "-addr=release-name-loki-gateway.default.svc.cluster.local.:80",
    #                                             "-labelname=pod",
    #                                             "-labelvalue=$(POD_NAME)",
    #                                             "-user=self-monitoring",
    #                                             "-tenant-id=self-monitoring",
    #                                             "-pass=",
    #                                             "-push=true"
    #                                           ],
    #                                       env =
    #                                         [
    #                                             {
    #                                               name = "POD_NAME",
    #                                               valueFrom =
    #                                                 {
    #                                                     fieldRef =
    #                                                       {
    #                                                           fieldPath =
    #                                                             "metadata.name",
    #                                                         },
    #                                                   },
    #                                             }
    #                                           ],
    #                                       image =
    #                                         "docker.io/grafana/loki-canary:3.3.2",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "loki-canary",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 3500,
    #                                               name = "http-metrics",
    #                                               protocol = "TCP",
    #                                             }
    #                                           ],
    #                                       readinessProbe =
    #                                         {
    #                                             httpGet =
    #                                               {
    #                                                   path = "/metrics",
    #                                                   port = "http-metrics",
    #                                                 },
    #                                             initialDelaySeconds = 15,
    #                                             timeoutSeconds = 1,
    #                                           },
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                       volumeMounts = null,
    #                                     }
    #                                   ],
    #                               securityContext =
    #                                 {
    #                                     fsGroup = 10001,
    #                                     runAsGroup = 10001,
    #                                     runAsNonRoot = true,
    #                                     runAsUser = 10001,
    #                                   },
    #                               serviceAccountName = "loki-canary",
    #                               volumes = null,
    #                             },
    #                       },
    #                   updateStrategy =
    #                     {
    #                         rollingUpdate = { maxUnavailable = 1, },
    #                         type = "RollingUpdate",
    #                       },
    #                 },
    #           },
    #       loki-canary-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "canary",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-canary",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   ports =
    #                     [
    #                         {
    #                           name = "http-metrics",
    #                           port = 3500,
    #                           protocol = "TCP",
    #                           targetPort = "http-metrics",
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" = "canary",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       loki-canary-serviceaccount =
    #         {
    #             apiVersion = "v1",
    #             automountServiceAccountToken = true,
    #             kind = "ServiceAccount",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "canary",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-canary",
    #                   namespace = "default",
    #                 },
    #           },
    #       loki-configmap =
    #         {
    #             apiVersion = "v1",
    #             data =
    #               {
    #                   "config.yaml" =
    #                     "\nauth_enabled: true\nbloom_build:\n  builder:\n    planner_address: loki-backend-headless.default.svc.cluster.local:9095\n  enabled: false\nbloom_gateway:\n  client:\n    addresses: dnssrvnoa+_grpc._tcp.loki-backend-headless.default.svc.cluster.local\n  enabled: false\nchunk_store_config:\n  chunk_cache_config:\n    background:\n      writeback_buffer: 500000\n      writeback_goroutines: 1\n      writeback_size_limit: 500MB\n    default_validity: 0s\n    memcached:\n      batch_size: 4\n      parallelism: 5\n    memcached_client:\n      addresses: dnssrvnoa+_memcached-client._tcp.release-name-loki-chunks-cache.default.svc\n      consistent_hash: true\n      max_idle_conns: 72\n      timeout: 2000ms\ncommon:\n  compactor_address: 'http://loki-backend:3100'\n  path_prefix: /var/loki\n  replication_factor: 3\n  storage:\n    s3:\n      access_key_id: enterprise-logs\n      bucketnames: chunks\n      endpoint: release-name-minio.default.svc:9000\n      insecure: true\n      s3forcepathstyle: true\n      secret_access_key: supersecret\nfrontend:\n  scheduler_address: \"\"\n  tail_proxy_url: \"\"\nfrontend_worker:\n  scheduler_address: \"\"\nindex_gateway:\n  mode: simple\ningester:\n  chunk_encoding: snappy\nlimits_config:\n  max_cache_freshness_per_query: 10m\n  query_timeout: 300s\n  reject_old_samples: true\n  reject_old_samples_max_age: 168h\n  split_queries_by_interval: 15m\n  volume_enabled: true\nmemberlist:\n  join_members:\n  - loki-memberlist\npattern_ingester:\n  enabled: false\nquerier:\n  max_concurrent: 4\nquery_range:\n  align_queries_with_step: true\n  cache_results: true\n  results_cache:\n    cache:\n      background:\n        writeback_buffer: 500000\n        writeback_goroutines: 1\n        writeback_size_limit: 500MB\n      default_validity: 12h\n      memcached_client:\n        addresses: dnssrvnoa+_memcached-client._tcp.release-name-loki-results-cache.default.svc\n        consistent_hash: true\n        timeout: 500ms\n        update_interval: 1m\nruler:\n  storage:\n    s3:\n      bucketnames: ruler\n    type: s3\n  wal:\n    dir: /var/loki/ruler-wal\nruntime_config:\n  file: /etc/loki/runtime-config/runtime-config.yaml\nschema_config:\n  configs:\n  - from: \"2024-04-01\"\n    index:\n      period: 24h\n      prefix: loki_index_\n    object_store: s3\n    schema: v13\n    store: tsdb\nserver:\n  grpc_listen_port: 9095\n  http_listen_port: 3100\n  http_server_read_timeout: 600s\n  http_server_write_timeout: 600s\nstorage_config:\n  bloom_shipper:\n    working_directory: /var/loki/data/bloomshipper\n  boltdb_shipper:\n    index_gateway_client:\n      server_address: dns+loki-backend-headless.default.svc.cluster.local:9095\n  hedging:\n    at: 250ms\n    max_per_second: 20\n    up_to: 3\n  tsdb_shipper:\n    index_gateway_client:\n      server_address: dns+loki-backend-headless.default.svc.cluster.local:9095\ntracing:\n  enabled: true\n",
    #                 },
    #             kind = "ConfigMap",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki",
    #                   namespace = "default",
    #                 },
    #           },
    #       loki-helm-test-pod =
    #         {
    #             apiVersion = "v1",
    #             kind = "Pod",
    #             metadata =
    #               {
    #                   annotations = { "helm.sh/hook" = "test", },
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "helm-test",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-helm-test",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   containers =
    #                     [
    #                         {
    #                           args = [ "-test.v" ],
    #                           env =
    #                             [
    #                                 {
    #                                   name = "CANARY_SERVICE_ADDRESS",
    #                                   value = "http://loki-canary:3500/metrics",
    #                                 },
    #                                 {
    #                                   name = "CANARY_PROMETHEUS_ADDRESS",
    #                                   value = "",
    #                                 },
    #                                 {
    #                                   name = "CANARY_TEST_TIMEOUT",
    #                                   value = "1m",
    #                                 }
    #                               ],
    #                           image =
    #                             "docker.io/grafana/loki-helm-test:ewelch-distributed-helm-chart-17db5ee",
    #                           name = "loki-helm-test",
    #                         }
    #                       ],
    #                   restartPolicy = "Never",
    #                 },
    #           },
    #       loki-memberlist-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-memberlist",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   clusterIP = "None",
    #                   ports =
    #                     [
    #                         {
    #                           name = "tcp",
    #                           port = 7946,
    #                           protocol = "TCP",
    #                           targetPort = "http-memberlist",
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/part-of" = "memberlist",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       loki-read-deployment =
    #         {
    #             apiVersion = "apps/v1",
    #             kind = "Deployment",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/part-of" = "memberlist",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-read",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   replicas = 3,
    #                   revisionHistoryLimit = 10,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" = "read",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                   strategy =
    #                     {
    #                         rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
    #                       },
    #                   template =
    #                     {
    #                         metadata =
    #                           {
    #                               annotations =
    #                                 {
    #                                     "checksum/config" =
    #                                       "8e022d1bb18305adc32d2118555611c62482c449ddb8bb3a45ecdf549c651bf5",
    #                                   },
    #                               labels =
    #                                 {
    #                                     "app.kubernetes.io/component" = "read",
    #                                     "app.kubernetes.io/instance" =
    #                                       "release-name",
    #                                     "app.kubernetes.io/name" = "loki",
    #                                     "app.kubernetes.io/part-of" =
    #                                       "memberlist",
    #                                   },
    #                             },
    #                         spec =
    #                           {
    #                               affinity =
    #                                 {
    #                                     podAntiAffinity =
    #                                       {
    #                                           requiredDuringSchedulingIgnoredDuringExecution =
    #                                             [
    #                                                 {
    #                                                   labelSelector =
    #                                                     {
    #                                                         matchLabels =
    #                                                           {
    #                                                               "app.kubernetes.io/component" =
    #                                                                 "read",
    #                                                             },
    #                                                       },
    #                                                   topologyKey =
    #                                                     "kubernetes.io/hostname",
    #                                                 }
    #                                               ],
    #                                         },
    #                                   },
    #                               automountServiceAccountToken = true,
    #                               containers =
    #                                 [
    #                                     {
    #                                       args =
    #                                         [
    #                                             "-config.file=/etc/loki/config/config.yaml",
    #                                             "-target=read",
    #                                             "-legacy-read-mode=false",
    #                                             "-common.compactor-grpc-address=loki-backend.default.svc.cluster.local:9095"
    #                                           ],
    #                                       image = "docker.io/grafana/loki:3.3.2",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "loki",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 3100,
    #                                               name = "http-metrics",
    #                                               protocol = "TCP",
    #                                             },
    #                                             {
    #                                               containerPort = 9095,
    #                                               name = "grpc",
    #                                               protocol = "TCP",
    #                                             },
    #                                             {
    #                                               containerPort = 7946,
    #                                               name = "http-memberlist",
    #                                               protocol = "TCP",
    #                                             }
    #                                           ],
    #                                       readinessProbe =
    #                                         {
    #                                             httpGet =
    #                                               {
    #                                                   path = "/ready",
    #                                                   port = "http-metrics",
    #                                                 },
    #                                             initialDelaySeconds = 30,
    #                                             timeoutSeconds = 1,
    #                                           },
    #                                       resources = {},
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                       volumeMounts =
    #                                         [
    #                                             {
    #                                               mountPath = "/etc/loki/config",
    #                                               name = "config",
    #                                             },
    #                                             {
    #                                               mountPath =
    #                                                 "/etc/loki/runtime-config",
    #                                               name = "runtime-config",
    #                                             },
    #                                             {
    #                                               mountPath = "/tmp",
    #                                               name = "tmp",
    #                                             },
    #                                             {
    #                                               mountPath = "/var/loki",
    #                                               name = "data",
    #                                             }
    #                                           ],
    #                                     }
    #                                   ],
    #                               securityContext =
    #                                 {
    #                                     fsGroup = 10001,
    #                                     runAsGroup = 10001,
    #                                     runAsNonRoot = true,
    #                                     runAsUser = 10001,
    #                                   },
    #                               serviceAccountName = "loki",
    #                               terminationGracePeriodSeconds = 30,
    #                               volumes =
    #                                 [
    #                                     { emptyDir = {}, name = "tmp", },
    #                                     { emptyDir = {}, name = "data", },
    #                                     {
    #                                       configMap =
    #                                         {
    #                                             items =
    #                                               [
    #                                                   {
    #                                                     key = "config.yaml",
    #                                                     path = "config.yaml",
    #                                                   }
    #                                                 ],
    #                                             name = "loki",
    #                                           },
    #                                       name = "config",
    #                                     },
    #                                     {
    #                                       configMap = { name = "loki-runtime", },
    #                                       name = "runtime-config",
    #                                     }
    #                                   ],
    #                             },
    #                       },
    #                 },
    #           },
    #       loki-read-headless-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "prometheus.io/service-monitor" = "false",
    #                         variant = "headless",
    #                       },
    #                   name = "loki-read-headless",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   clusterIP = "None",
    #                   ports =
    #                     [
    #                         {
    #                           name = "http-metrics",
    #                           port = 3100,
    #                           protocol = "TCP",
    #                           targetPort = "http-metrics",
    #                         },
    #                         {
    #                           appProtocol = "tcp",
    #                           name = "grpc",
    #                           port = 9095,
    #                           protocol = "TCP",
    #                           targetPort = "grpc",
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       loki-read-poddisruptionbudget =
    #         {
    #             apiVersion = "policy/v1",
    #             kind = "PodDisruptionBudget",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-read",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   maxUnavailable = 1,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" = "read",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                 },
    #           },
    #       loki-read-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-read",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   ports =
    #                     [
    #                         {
    #                           name = "http-metrics",
    #                           port = 3100,
    #                           protocol = "TCP",
    #                           targetPort = "http-metrics",
    #                         },
    #                         {
    #                           name = "grpc",
    #                           port = 9095,
    #                           protocol = "TCP",
    #                           targetPort = "grpc",
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" = "read",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       loki-runtime-configmap =
    #         {
    #             apiVersion = "v1",
    #             data = { "runtime-config.yaml" = "{}\n", },
    #             kind = "ConfigMap",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki-runtime",
    #                   namespace = "default",
    #                 },
    #           },
    #       loki-serviceaccount =
    #         {
    #             apiVersion = "v1",
    #             automountServiceAccountToken = true,
    #             kind = "ServiceAccount",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "loki",
    #                   namespace = "default",
    #                 },
    #           },
    #       minio-sa-serviceaccount =
    #         {
    #             apiVersion = "v1",
    #             kind = "ServiceAccount",
    #             metadata = { name = "minio-sa", },
    #           },
    #       release-name-loki-chunks-cache-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = {},
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-chunks-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-chunks-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   clusterIP = "None",
    #                   ports =
    #                     [
    #                         {
    #                           name = "memcached-client",
    #                           port = 11211,
    #                           targetPort = 11211,
    #                         },
    #                         {
    #                           name = "http-metrics",
    #                           port = 9150,
    #                           targetPort = 9150,
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-chunks-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       release-name-loki-chunks-cache-statefulset =
    #         {
    #             apiVersion = "apps/v1",
    #             kind = "StatefulSet",
    #             metadata =
    #               {
    #                   annotations = {},
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-chunks-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                         name = "memcached-chunks-cache",
    #                       },
    #                   name = "release-name-loki-chunks-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   podManagementPolicy = "Parallel",
    #                   replicas = 1,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" =
    #                                 "memcached-chunks-cache",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                               name = "memcached-chunks-cache",
    #                             },
    #                       },
    #                   serviceName = "release-name-loki-chunks-cache",
    #                   template =
    #                     {
    #                         metadata =
    #                           {
    #                               annotations = null,
    #                               labels =
    #                                 {
    #                                     "app.kubernetes.io/component" =
    #                                       "memcached-chunks-cache",
    #                                     "app.kubernetes.io/instance" =
    #                                       "release-name",
    #                                     "app.kubernetes.io/name" = "loki",
    #                                     name = "memcached-chunks-cache",
    #                                   },
    #                             },
    #                         spec =
    #                           {
    #                               affinity = {},
    #                               containers =
    #                                 [
    #                                     {
    #                                       args =
    #                                         [
    #                                             "-m 8192",
    #                                             "--extended=modern,track_sizes",
    #                                             "-I 5m",
    #                                             "-c 16384",
    #                                             "-v",
    #                                             "-u 11211"
    #                                           ],
    #                                       env = null,
    #                                       envFrom = null,
    #                                       image = "memcached:1.6.33-alpine",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "memcached",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 11211,
    #                                               name = "client",
    #                                             }
    #                                           ],
    #                                       resources =
    #                                         {
    #                                             limits = { memory = "9830Mi", },
    #                                             requests =
    #                                               {
    #                                                   cpu = "500m",
    #                                                   memory = "9830Mi",
    #                                                 },
    #                                           },
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                     },
    #                                     {
    #                                       args =
    #                                         [
    #                                             "--memcached.address=localhost:11211",
    #                                             "--web.listen-address=0.0.0.0:9150"
    #                                           ],
    #                                       image =
    #                                         "prom/memcached-exporter:v0.15.0",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "exporter",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 9150,
    #                                               name = "http-metrics",
    #                                             }
    #                                           ],
    #                                       resources =
    #                                         { limits = {}, requests = {}, },
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                     }
    #                                   ],
    #                               initContainers = [  ],
    #                               nodeSelector = {},
    #                               securityContext =
    #                                 {
    #                                     fsGroup = 11211,
    #                                     runAsGroup = 11211,
    #                                     runAsNonRoot = true,
    #                                     runAsUser = 11211,
    #                                   },
    #                               serviceAccountName = "loki",
    #                               terminationGracePeriodSeconds = 60,
    #                               tolerations = [  ],
    #                               topologySpreadConstraints = [  ],
    #                             },
    #                       },
    #                   updateStrategy = { type = "RollingUpdate", },
    #                 },
    #           },
    #       release-name-loki-clusterrole-clusterrole =
    #         {
    #             apiVersion = "rbac.authorization.k8s.io/v1",
    #             kind = "ClusterRole",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-clusterrole",
    #                 },
    #             rules =
    #               [
    #                   {
    #                     apiGroups = [ "" ],
    #                     resources = [ "configmaps", "secrets" ],
    #                     verbs = [ "get", "watch", "list" ],
    #                   }
    #                 ],
    #           },
    #       release-name-loki-clusterrolebinding-clusterrolebinding =
    #         {
    #             apiVersion = "rbac.authorization.k8s.io/v1",
    #             kind = "ClusterRoleBinding",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-clusterrolebinding",
    #                 },
    #             roleRef =
    #               {
    #                   apiGroup = "rbac.authorization.k8s.io",
    #                   kind = "ClusterRole",
    #                   name = "release-name-loki-clusterrole",
    #                 },
    #             subjects =
    #               [
    #                   {
    #                     kind = "ServiceAccount",
    #                     name = "loki",
    #                     namespace = "default",
    #                   }
    #                 ],
    #           },
    #       release-name-loki-gateway-configmap =
    #         {
    #             apiVersion = "v1",
    #             data =
    #               {
    #                   "nginx.conf" =
    #                     "worker_processes  5;  ## Default: 1\nerror_log  /dev/stderr;\npid        /tmp/nginx.pid;\nworker_rlimit_nofile 8192;\n\nevents {\n  worker_connections  4096;  ## Default: 1024\n}\n\nhttp {\n  client_body_temp_path /tmp/client_temp;\n  proxy_temp_path       /tmp/proxy_temp_path;\n  fastcgi_temp_path     /tmp/fastcgi_temp;\n  uwsgi_temp_path       /tmp/uwsgi_temp;\n  scgi_temp_path        /tmp/scgi_temp;\n\n  client_max_body_size  4M;\n\n  proxy_read_timeout    600; ## 10 minutes\n  proxy_send_timeout    600;\n  proxy_connect_timeout 600;\n\n  proxy_http_version    1.1;\n\n  default_type application/octet-stream;\n  log_format   main '$remote_addr - $remote_user [$time_local]  $status '\n        '\"$request\" $body_bytes_sent \"$http_referer\" '\n        '\"$http_user_agent\" \"$http_x_forwarded_for\"';\n  access_log   /dev/stderr  main;\n\n  sendfile     on;\n  tcp_nopush   on;\n  resolver kube-dns.kube-system.svc.cluster.local.;\n  \n\n  server {\n    listen             8080;\n    listen             [::]:8080;\n\n    location = / {\n      return 200 'OK';\n      auth_basic off;\n    }\n\n    ########################################################\n    # Configure backend targets# Distributor\n    location = /api/prom/push {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /loki/api/v1/push {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /distributor/ring {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /otlp/v1/logs {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # Ingester\n    location = /flush {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n    location ^~ /ingester/ {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /ingester {\n      internal;        # to suppress 301\n    }\n\n    # Ring\n    location = /ring {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # MemberListKV\n    location = /memberlist {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # Ruler\n    location = /ruler/ring {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /api/prom/rules {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location ^~ /api/prom/rules/ {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /loki/api/v1/rules {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location ^~ /loki/api/v1/rules/ {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /prometheus/api/v1/alerts {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /prometheus/api/v1/rules {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # Compactor\n    location = /compactor/ring {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /loki/api/v1/delete {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /loki/api/v1/cache/generation_numbers {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # IndexGateway\n    location = /indexgateway/ring {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # QueryScheduler\n    location = /scheduler/ring {\n      proxy_pass       http://loki-backend.default.svc.cluster.local:3100$request_uri;\n    }\n\n    # Config\n    location = /config {\n      proxy_pass       http://loki-write.default.svc.cluster.local:3100$request_uri;\n    }\n\n\n    # QueryFrontend, Querier\n    location = /api/prom/tail {\n      proxy_pass       http://loki-read.default.svc.cluster.local:3100$request_uri;\n      proxy_set_header Upgrade $http_upgrade;\n      proxy_set_header Connection \"upgrade\";\n    }\n    location = /loki/api/v1/tail {\n      proxy_pass       http://loki-read.default.svc.cluster.local:3100$request_uri;\n      proxy_set_header Upgrade $http_upgrade;\n      proxy_set_header Connection \"upgrade\";\n    }\n    location ^~ /api/prom/ {\n      proxy_pass       http://loki-read.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /api/prom {\n      internal;        # to suppress 301\n    }\n    location ^~ /loki/api/v1/ {\n      proxy_pass       http://loki-read.default.svc.cluster.local:3100$request_uri;\n    }\n    location = /loki/api/v1 {\n      internal;        # to suppress 301\n    }\n  }\n}\n",
    #                 },
    #             kind = "ConfigMap",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "gateway",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-gateway",
    #                   namespace = "default",
    #                 },
    #           },
    #       release-name-loki-gateway-deployment =
    #         {
    #             apiVersion = "apps/v1",
    #             kind = "Deployment",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "gateway",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-gateway",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   replicas = 1,
    #                   revisionHistoryLimit = 10,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" = "gateway",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                   strategy = { type = "RollingUpdate", },
    #                   template =
    #                     {
    #                         metadata =
    #                           {
    #                               annotations =
    #                                 {
    #                                     "checksum/config" =
    #                                       "afcb9bfc2815e2b94ccffd596b5dd75cc464bc5c564681571214bccff9c1951a",
    #                                   },
    #                               labels =
    #                                 {
    #                                     "app.kubernetes.io/component" = "gateway",
    #                                     "app.kubernetes.io/instance" =
    #                                       "release-name",
    #                                     "app.kubernetes.io/name" = "loki",
    #                                   },
    #                             },
    #                         spec =
    #                           {
    #                               affinity =
    #                                 {
    #                                     podAntiAffinity =
    #                                       {
    #                                           requiredDuringSchedulingIgnoredDuringExecution =
    #                                             [
    #                                                 {
    #                                                   labelSelector =
    #                                                     {
    #                                                         matchLabels =
    #                                                           {
    #                                                               "app.kubernetes.io/component" =
    #                                                                 "gateway",
    #                                                             },
    #                                                       },
    #                                                   topologyKey =
    #                                                     "kubernetes.io/hostname",
    #                                                 }
    #                                               ],
    #                                         },
    #                                   },
    #                               containers =
    #                                 [
    #                                     {
    #                                       image =
    #                                         "docker.io/nginxinc/nginx-unprivileged:1.27-alpine",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "nginx",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 8080,
    #                                               name = "http-metrics",
    #                                               protocol = "TCP",
    #                                             }
    #                                           ],
    #                                       readinessProbe =
    #                                         {
    #                                             httpGet =
    #                                               {
    #                                                   path = "/",
    #                                                   port = "http-metrics",
    #                                                 },
    #                                             initialDelaySeconds = 15,
    #                                             timeoutSeconds = 1,
    #                                           },
    #                                       resources = {},
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                       volumeMounts =
    #                                         [
    #                                             {
    #                                               mountPath = "/etc/nginx",
    #                                               name = "config",
    #                                             },
    #                                             {
    #                                               mountPath = "/tmp",
    #                                               name = "tmp",
    #                                             },
    #                                             {
    #                                               mountPath =
    #                                                 "/docker-entrypoint.d",
    #                                               name =
    #                                                 "docker-entrypoint-d-override",
    #                                             }
    #                                           ],
    #                                     }
    #                                   ],
    #                               enableServiceLinks = true,
    #                               securityContext =
    #                                 {
    #                                     fsGroup = 101,
    #                                     runAsGroup = 101,
    #                                     runAsNonRoot = true,
    #                                     runAsUser = 101,
    #                                   },
    #                               serviceAccountName = "loki",
    #                               terminationGracePeriodSeconds = 30,
    #                               volumes =
    #                                 [
    #                                     {
    #                                       configMap =
    #                                         {
    #                                             name =
    #                                               "release-name-loki-gateway",
    #                                           },
    #                                       name = "config",
    #                                     },
    #                                     { emptyDir = {}, name = "tmp", },
    #                                     {
    #                                       emptyDir = {},
    #                                       name = "docker-entrypoint-d-override",
    #                                     }
    #                                   ],
    #                             },
    #                       },
    #                 },
    #           },
    #       release-name-loki-gateway-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "gateway",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-gateway",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   ports =
    #                     [
    #                         {
    #                           name = "http-metrics",
    #                           port = 80,
    #                           protocol = "TCP",
    #                           targetPort = "http-metrics",
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" = "gateway",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       release-name-loki-memcached-chunks-cache-poddisruptionbudget =
    #         {
    #             apiVersion = "policy/v1",
    #             kind = "PodDisruptionBudget",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-chunks-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   name = "release-name-loki-memcached-chunks-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   maxUnavailable = 1,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" =
    #                                 "memcached-chunks-cache",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                 },
    #           },
    #       release-name-loki-memcached-results-cache-poddisruptionbudget =
    #         {
    #             apiVersion = "policy/v1",
    #             kind = "PodDisruptionBudget",
    #             metadata =
    #               {
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-results-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   name = "release-name-loki-memcached-results-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   maxUnavailable = 1,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" =
    #                                 "memcached-results-cache",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                             },
    #                       },
    #                 },
    #           },
    #       release-name-loki-query-scheduler-discovery-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = null,
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" = "backend",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "prometheus.io/service-monitor" = "false",
    #                       },
    #                   name = "release-name-loki-query-scheduler-discovery",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   clusterIP = "None",
    #                   ports =
    #                     [
    #                         {
    #                           name = "http-metrics",
    #                           port = 3100,
    #                           protocol = "TCP",
    #                           targetPort = "http-metrics",
    #                         },
    #                         {
    #                           name = "grpc",
    #                           port = 9095,
    #                           protocol = "TCP",
    #                           targetPort = "grpc",
    #                         }
    #                       ],
    #                   publishNotReadyAddresses = true,
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" = "backend",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       release-name-loki-results-cache-service =
    #         {
    #             apiVersion = "v1",
    #             kind = "Service",
    #             metadata =
    #               {
    #                   annotations = {},
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-results-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                       },
    #                   name = "release-name-loki-results-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   clusterIP = "None",
    #                   ports =
    #                     [
    #                         {
    #                           name = "memcached-client",
    #                           port = 11211,
    #                           targetPort = 11211,
    #                         },
    #                         {
    #                           name = "http-metrics",
    #                           port = 9150,
    #                           targetPort = 9150,
    #                         }
    #                       ],
    #                   selector =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-results-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                       },
    #                   type = "ClusterIP",
    #                 },
    #           },
    #       release-name-loki-results-cache-statefulset =
    #         {
    #             apiVersion = "apps/v1",
    #             kind = "StatefulSet",
    #             metadata =
    #               {
    #                   annotations = {},
    #                   labels =
    #                     {
    #                         "app.kubernetes.io/component" =
    #                           "memcached-results-cache",
    #                         "app.kubernetes.io/instance" = "release-name",
    #                         "app.kubernetes.io/name" = "loki",
    #                         "app.kubernetes.io/version" = "3.3.2",
    #                         "helm.sh/chart" = "loki-6.24.0",
    #                         name = "memcached-results-cache",
    #                       },
    #                   name = "release-name-loki-results-cache",
    #                   namespace = "default",
    #                 },
    #             spec =
    #               {
    #                   podManagementPolicy = "Parallel",
    #                   replicas = 1,
    #                   selector =
    #                     {
    #                         matchLabels =
    #                           {
    #                               "app.kubernetes.io/component" =
    #                                 "memcached-results-cache",
    #                               "app.kubernetes.io/instance" = "release-name",
    #                               "app.kubernetes.io/name" = "loki",
    #                               name = "memcached-results-cache",
    #                             },
    #                       },
    #                   serviceName = "release-name-loki-results-cache",
    #                   template =
    #                     {
    #                         metadata =
    #                           {
    #                               annotations = null,
    #                               labels =
    #                                 {
    #                                     "app.kubernetes.io/component" =
    #                                       "memcached-results-cache",
    #                                     "app.kubernetes.io/instance" =
    #                                       "release-name",
    #                                     "app.kubernetes.io/name" = "loki",
    #                                     name = "memcached-results-cache",
    #                                   },
    #                             },
    #                         spec =
    #                           {
    #                               affinity = {},
    #                               containers =
    #                                 [
    #                                     {
    #                                       args =
    #                                         [
    #                                             "-m 1024",
    #                                             "--extended=modern,track_sizes",
    #                                             "-I 5m",
    #                                             "-c 16384",
    #                                             "-v",
    #                                             "-u 11211"
    #                                           ],
    #                                       env = null,
    #                                       envFrom = null,
    #                                       image = "memcached:1.6.33-alpine",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "memcached",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 11211,
    #                                               name = "client",
    #                                             }
    #                                           ],
    #                                       resources =
    #                                         {
    #                                             limits = { memory = "1229Mi", },
    #                                             requests =
    #                                               {
    #                                                   cpu = "500m",
    #                                                   memory = "1229Mi",
    #                                                 },
    #                                           },
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                     },
    #                                     {
    #                                       args =
    #                                         [
    #                                             "--memcached.address=localhost:11211",
    #                                             "--web.listen-address=0.0.0.0:9150"
    #                                           ],
    #                                       image =
    #                                         "prom/memcached-exporter:v0.15.0",
    #                                       imagePullPolicy = "IfNotPresent",
    #                                       name = "exporter",
    #                                       ports =
    #                                         [
    #                                             {
    #                                               containerPort = 9150,
    #                                               name = "http-metrics",
    #                                             }
    #                                           ],
    #                                       resources =
    #                                         { limits = {}, requests = {}, },
    #                                       securityContext =
    #                                         {
    #                                             allowPrivilegeEscalation = false,
    #                                             capabilities =
    #                                               { drop = [ "ALL" ], },
    #                                             readOnlyRootFilesystem = true,
    #                                           },
    #                                     }
    #                                   ],
    #                               initContainers = [  ],
    #                               nodeSelector = {},
    #                               securityContext =
    #                                 {
    #                                     fsGroup = 11211,
    #                                     runAsGroup = 11211,
    #                                     runAsNonRoot = true,
    #                                     runAsUser = 11211,
    #                                   },
    #                               serviceAccountName = "loki",
    #                               terminationGracePeriodSeconds = 60,
    #                               tolerations = [  ],
    #                               topologySpreadConstraints = [  ],
    #                             },
    #                       },
    #                   updateStrategy = { type = "RollingUpdate", },
    #                 },
    #           },
    #     },
  }
