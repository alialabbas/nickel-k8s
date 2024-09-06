let k8s = import "generated.ncl" in let service = import "networking.ncl" in let c = k8s.v1.Service & service.v1.Service in {
  apiVersion | force = "v1",
  kind = "Service",
  metadata = {
    name = "test",
    namespace = "test"
  },
  spec = {
    internalTrafficPolicy = "Local",
    ports = [
      {
        name = "jaeger-compact",
        port = 6831,
        protocol = "UDP",
        targetPort = 6831,
      },
      {
        name = "jaeger-grpc",
        port = 14250,
        protocol = "TCP",
        targetPort = 14250,
      },
      {
        name = "jaeger-thrift",
        port = 14268,
        protocol = "TCP",
        targetPort = 14268,
      },
      {
        appProtocol = "grpc",
        name = "otlp",
        port = 4317,
        protocol = "TCP",
        targetPort = 4317,
      },
      {
        name = "otlp-http",
        port = 4319,
        protocol = "TCP",
        targetPort = 4318,
      },
      {
        name = "zipkin",
        port = 9411,
        protocol = "TCP",
        targetPort = 9411,
      },
    ],
    selector = {},
    type = "ClusterIP",
  },
} | k8s.v1.Service | (std.contract.custom (fun label value => 'Ok (std.record.has_field "status" value)))
