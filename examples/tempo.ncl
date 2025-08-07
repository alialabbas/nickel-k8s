let lib = import "../lib.ncl" in
{
  inputs
    | {
      version | doc "tempo version to use" | lib.semver.SemanticVersion | default = "2.8.1",
      continuous-testing | { enabled | Bool | default = true, version | String | default = "2.6.1" } | default = {},
      mode
        | doc "Run mode for tempo, scalable is a read-write distribution and distributed is the microservices mode"
        | std.enum.TagOrString
        | [| 'single-binary, 'distributed, |]
        | default
        = 'distributed,
      # TODO: minimal config and just force certain values...
      config
        | { memberlist.join_members | force = ["dns+%{manifests.gossip-ring-service.metadata.name}:%{std.string.from_number inputs.config.memberlist.bind_port}"], .. }
        & (
          if inputs.mode == 'distributed then
            {
              querier.frontend_worker.frontend_address | force = "%{manifests.query-frontend-service-headless.metadata.name}:%{inputs.config.server.grpc_listen_port}",
            }
          else
            {}
        )
        = import "./tempo/tempo.yaml",
    }
    = {},

  output = {
    endpoints =
      let port = ":%{std.string.from_number inputs.config.server.http_listen_port}" in
      {
        base =
          inputs.mode
          |> match {
            'distributed => manifests.distributor-service.metadata.name,
            'single-binary => manifests.single-binary-service.metadata.name,
          },
        otlp = base ++ ":4317",
        write = base ++ port,
        reader =
          inputs.mode
          |> match {
            'distributed => manifests.query-frontend-service.metadata.name ++ port,
            'single-binary => base ++ port
          }
      }
  },

  release_metadata = {},
  manifests =
    (
      if inputs.continuous-testing.enabled then
        (import "./tempo/continuous-test.ncl") inputs.version output.endpoints.base output.endpoints.reader
      else
        {}
    )
    & (
      inputs.mode
      |> match {
        'distributed => (import "./tempo/distributed.ncl") inputs,
        'single-binary => (import "./tempo/single-binary.ncl") inputs,
      }
    ),
} | (import "../kube.ncl").Release
