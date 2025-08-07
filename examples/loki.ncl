# TODO:
# replication factor opens an interesting point
# How do we make sure the user's applied contract hasn't changed in the process
# the issue is replicas is applied initially on the initial boot
# but then once the value is set, nothing really will change?
# this make it impossible for something like a contract to capture if the replica count + replication_factor make sense or not
let LokiConfig = import "./loki/config.ncl" in
{
  inputs
    | {
      version | doc "version of loki to run" | String | default = "3.5.1",
      continuous-testing
        | doc "Canary is a continuous testing tool to ensure loki can ingest logs correctly"
        | { enabled | Bool | default = true, version | String | default = "3.3.2" }
        | default
        = {},
      mode
        | doc "Run mode for loki, scalable is a read-write distribution and distributed is the microservices mode"
        | std.enum.TagOrString
        | [| 'single-binary, 'distributed, 'scalable |]
        | default
        = 'distributed,
      # TODO: similar to pyroscope, anything that is not single-binary can't really operate without blob storage
      # What about multi replica setup + single binary?
      # TODO: this config should be minimal
      config
        | LokiConfig
        | { memberlist.join_members | force = [manifests.memberlist-service.metadata.name, ], .. }
        & (
          if mode == 'distributed then
            # TODO: These should be written with as some sort of FrozenValues. The system will set their defaults but also we want a clear error message on why they are not overridable
            # if the check is in the contract, it shouldn't matter where the value is coming from
            {
              common.compactor_address | force = "http://%{manifests.compactor-service.metadata.name}:%{inputs.config.server.http_listen_port}",
              frontend.tail_proxy_url | force =
                "http://"
                ++ manifests.querier-service.metadata.name
                ++ ":"
                ++ (std.string.from_number config.server.grpc_listen_port),
              # frontend.scheduler_address | force =
              #   "http://"
              #   ++ manifests.query-scheduler.metadata.name
              #   ++ ":"
              #   ++ (std.string.from_number config.server.grpc_listen_port),
              frontend_worker.frontend_address | force =
                manifests.query-frontend-headless-service.metadata.name
                ++ ":"
                ++ (std.string.from_number config.server.grpc_listen_port),
              # frontend_worker.scheduler_address | force =
              #   "http://"
              #   ++ manifests.query-scheduler.metadata.name
              #   ++ ":"
              #   ++ (std.string.from_number config.server.grpc_listen_port),
            }
          else if mode == 'scalable then
            {
              common.compactor_address | force = "http://%{manifests.backend-service.metadata.name}:%{inputs.config.server.http_listen_port}",
            }
          else
            {}
        )
        = import "./loki.yaml",
    }
    | default
    = {},

  output = {
    endpoints =
      let port = ":%{std.string.from_number inputs.config.server.http_listen_port}" in
      {
        writer =
          inputs.mode
          |> match {
            'distributed => manifests.distributor-service.metadata.name ++ port,
            'scalable => manifests.write-service.metadata.name ++ port,
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
          },
        reader =
          inputs.mode
          |> match {
            'distributed => manifests.query-frontend-service.metadata.name ++ port,
            'scalable => manifests.read-service.metadata.name ++ port,
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
          },
      }
  },
  release_metadata = {},
  manifests =
    (
      if inputs.continuous-testing.enabled then
        (
          (import "./loki/canary.ncl")
            inputs.continuous-testing.version
            output.endpoints.writer
        )
      else
        {}
    )
    & (
      inputs.mode
      |> match {
        'distributed => (import "./loki/distributed.ncl") inputs,
        'scalable => (import "./loki/scalable.ncl") inputs,
        'single-binary => (import "./loki/single-binary.ncl") inputs
      }
    ),
} | (import "../kube.ncl").Release
