let component = { name | String, stability | { logs | String, metrics | String, traces | String }, } in

let cfg
  | {
    buildinfo | { .. },
    receivers | Array component,
    exporters | Array component,
    processors | Array component,
    extensions | Array { name | String, stability | { extension | String } }, # TODO: this could be folded fup if the record fields are enumerated
    # A connector is a receiver and exporter
    # the original receiver + exporters map should be kept clean
    # instead we want another conditional check for the pipeline to go over the connector and see if it allows the pipeline graph to go from signal to signal
    # i.e. connector.receivers = someName === For the signal basically
    connectors
      | Array {
        name | String,
        stability
          | { _ | String }
          | (import "../types.ncl").Records.FieldsAreOfType
            (
              std.contract.Sequence
                [
                  std.enum.TagOrString,
                  [|
                    'logs-to-logs,
                    'logs-to-metrics,
                    'logs-to-traces,
                    'metrics-to-metrics,
                    'metrics-to-logs,
                    'metrics-to-traces,
                    'traces-to-traces,
                    'traces-to-logs,
                    'traces-to-metrics
                  |]
                ]
            )
      },
  }
  = import "components.yaml"
  in
# x-to-y => means from exporter x we go to receiver y, logs-to-metrics mean for logs this is allowed as exporter but logs-to-logs = Undefined means this won't go to the same signal
# we will model connectors as the following => receivers = [valid]
# for the exceptions for example
# we want to export to metrics and logs, but not traces
# They are weird, it should be like what i said, we should just care what is what for the signal
let connectorValidFor = fun type connector =>
  connector
  |> std.record.to_array
  |> std.array.filter (fun e => (std.string.is_match "%{type}-to-\\.*" e.field) && e.value != "Undefined")
  |> std.array.length > 0
  # |> std.record.from_array
  # |> std.array.filter (fun e => !std.string.is_match "\\.*to-%{type}" e.value)
in
cfg.connectors |> std.array.fold_right (fun e acc => if (connectorValidFor "logs" e.stability) then [e.name] @ acc else acc) []
# cfg.connectors |> std.array.map (fun e => connectorValidFor "logs" e.stability)
