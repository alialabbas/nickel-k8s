let lib = import "../lib.ncl" in
let PyroscopeConfig = import "./pyroscope/config.ncl" in
{
  inputs
    | {
      version | doc "pyroscope version to use" | lib.semver.SemanticVersion | default = "1.14.0",
      continuous-testing | { enabled | Bool | default = true, } | default = {},
      mode
        | doc "Run mode for pyroscope, scalable is a read-write distribution and distributed is the microservices mode"
        | std.enum.TagOrString
        | [| 'single-binary, 'distributed, 'scalable |]
        | default
        = 'distributed,
      config
        | PyroscopeConfig
        & (
          mode
          |> match {
            'distributed => { storage },
            _ => {},
          }
        )
        # assume the list of members and based on the final artifact name
        & { memberlist.join_members = ["%{output.endpoints.memberlist}:%{memberlist.bind_port}"], }
        = import "./pyroscope/pyroscope.yaml",
    },

  output = {
    endpoints =
      let port = ":%{std.string.from_number inputs.config.server.http_listen_port}" in
      {
        writer =
          inputs.mode
          |> match {
            'distributed => manifests.distributor-service.metadata.name ++ port,
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
          },
        reader =
          inputs.mode
          |> match {
            'distributed => manifests.query-frontend-service.metadata.name ++ port,
            'single-binary => manifests.single-binary-service.metadata.name ++ port,
          },
        memberlist = "dnssrv+%{manifests.memberlist-service.metadata.name}"
      }
  },

  manifests =
    inputs.mode
    |> match {
      'distributed => (import "./pyroscope/distributed.ncl") inputs,
      'single-binary => (import "./pyroscope/single-binary.ncl") inputs,
    },
} | (import "../kube.ncl").Release
