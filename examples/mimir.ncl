let lib = import "../lib.ncl" in
let MimirConfig = import "./mimir/config.ncl" in
{
  inputs
    | {
      version | doc "Mimir version to use" | lib.semver.SemanticVersion | default = "2.16.0",
      continuous-testing | { enabled | Bool | default = true, } | default = {},
      mode
        | doc m%"
        Run mode for mimir, scalable is a read-write distribution and distributed is the microservices mode

        'distributed => microservices mode, each target represent a single mimir component like ingester, querier, etc
        'scalable => separate read/write path
        'single-binary => low data volume environment
        'playground => ephemeral environment to bootstrap mimir and test it out
        "%
        | std.enum.TagOrString
        | [| 'single-binary, 'distributed, 'scalable |]
        | default
        = 'single-binary,
      config
        | doc "Standard mimir configuration. Note this data drive many parts in the configuration"
        | MimirConfig
        & { memberlist.join_members | force = ["dns+%{manifests.gossip-ring-service.metadata.name}:%{memberlist.bind_port}"], }
        & (
          if mode == 'distributed then
            {
              frontend.scheduler_address | force =
                manifests.query-scheduler-headless-service.metadata.name
                ++ ":"
                ++ (std.string.from_number config.server.grpc_listen_port),
              frontend_worker.scheduler_address | force =
                manifests.query-scheduler-headless-service.metadata.name
                ++ ":"
                ++ (std.string.from_number config.server.grpc_listen_port),
            }
          else
            {}
        )
        = (import "./mimir/mimir.yaml"),
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
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
            'scalable => manifests.write-service.metadata.name ++ port,
          },
        reader =
          inputs.mode
          |> match {
            'distributed => manifests.query-frontend-service.metadata.name ++ port,
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
            'scalable => manifests.read-service.metadata.name ++ port,
          },
      }
  },

  release_metadata = {},

  manifests =
    (
      if inputs.continuous-testing.enabled then
        (
          (import "./mimir/continuous-test.ncl")
            inputs
            output.endpoints.reader
            output.endpoints.writer
        )
      else
        {}
    )
    & (
      inputs.mode
      |> match {
        'distributed => (import "./mimir/distributed.ncl") inputs,
        'scalable => (import "./mimir/scalable.ncl") inputs,
        'single-binary => (import "./mimir/single-binary.ncl") inputs,
      }
    ),
}
