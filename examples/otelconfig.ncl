let component = { name | String, stability | { logs | String, metrics | String, traces | String }, module | String | optional, } in
let cfg
  | {
    buildinfo | { .. },
    receivers | Array component,
    exporters | Array component,
    processors | Array component,
    extensions | Array { name | String, stability | { extension | String }, module | String | optional },
    connectors
      | Array {
        name | String,
        module | String,
        stability
          | { _ | String }
          | std.record.FieldsMatch "^(logs-to-logs|logs-to-metrics|logs-to-traces|metrics-to-metrics|metrics-to-logs|metrics-to-traces|traces-to-traces|traces-to-logs|traces-to-metrics)$"
      },
    providers | { .. } | optional,
  }
  = import "components.yaml"
in
let signalComponent
  : String -> { exporters : Array String, receivers : Array String, processors : Array String, extensions : Array String, connectors : _ }
  = fun signal =>
    let fetcher = fun component =>
      std.array.fold_right
        (fun e acc => if std.record.get signal e.stability != "Undefined" then acc @ [e.name] else acc)
        []
        (std.record.get component cfg | _)
    in
    let connectorsAsExportersFor = fun type connector =>
      connector
      |> std.record.to_array
      |> std.array.filter (fun e => (std.string.is_match "%{type}-to-\\.*" e.field) && e.value != "Undefined")
      |> std.array.length > 0
    in
    let connectorsAsReceiversFor = fun type connector =>
      connector
      |> std.record.to_array
      |> std.array.filter (fun e => (std.string.is_match "\\.*-to-%{type}" e.field) && e.value != "Undefined")
      |> std.array.length > 0
    in
    {
      receivers = (fetcher "receivers") @ connectors.receivers,
      exporters = (fetcher "exporters") @ connectors.exporters,
      processors = (fetcher "processors"),
      extensions = (std.array.map (fun e => e.name) (cfg.extensions | _)),
      connectors.receivers = (cfg.connectors | _) |> std.array.fold_right (fun e acc => if (connectorsAsReceiversFor signal e.stability) then [e.name] @ acc else acc) [],
      connectors.exporters = (cfg.connectors | _) |> std.array.fold_right (fun e acc => if (connectorsAsExportersFor signal e.stability) then [e.name] @ acc else acc) [],
    }
in

let componentName
  : String -> String
  | doc "Simple Utility function to extract core opentel component name"
  = fun name =>
    name
    |> std.string.split "/"
    |> std.array.first
in

let Component = std.contract.Sequence [std.enum.TagOrString, [| 'receivers, 'processors, 'exporters, 'extensions, 'connectors |]] in

let ComponentValidation
  | Component -> Dyn
  = fun component =>
    std.contract.from_validator (fun value =>
      let component = std.to_string component in
      let configuredReceivers = std.record.fields value in
      let knownComponents = std.array.map (fun e => e.name) (std.record.get component cfg) in

      let has_invalid_component =
        std.array.try_fold_left
          (fun acc e =>
            let base_name = componentName e in
            if !std.array.elem base_name knownComponents then
              'Error base_name
            else
              'Ok null
          )
          ('Ok null)
          configuredReceivers
      in
      has_invalid_component
      |> match {
        'Ok _ => 'Ok,
        'Error r =>
          'Error {
            message = "%{component} `%{r}` doesn't exist in the known %{component} list",
            notes = knownComponents
          }
      }
    )
in

let PipelineNames =
  std.contract.from_validator (fun value =>
    let defined_pipelines = std.record.fields value in
    let has_invalid_pipeline_name =
      std.array.try_fold_left
        (fun acc e =>
          let type = componentName e in
          if type == "logs" || type == "metrics" || type == "traces" then
            'Ok null
          else
            'Error "Invalid pipeline name `%{e}` expected [logs traces metrics] or an suffixed version of them, e.g logs/example"
        )
        ('Ok value)
        defined_pipelines
    in
    has_invalid_pipeline_name
    |> match {
      'Ok _ => 'Ok,
      'Error msg => 'Error { message = msg },
    }
  )
in

let PipelineContract = fun configuredReceivers configuredExporters configuredProcessors configuredConnectors =>
  std.contract.custom (fun label value =>
    let knownComponents = {
      logs = signalComponent "logs",
      metrics = signalComponent "metrics",
      traces = signalComponent "traces",
    }
    in

    let Pipeline = fun name =>
      std.contract.custom (fun label pipeline =>
        let signal = componentName name in

        let componentValidForSignal = fun name type =>
          let availableComponents = std.record.get signal knownComponents in
          std.array.elem (componentName name) ((std.record.get availableComponents type) | Array String)
        in

        let ConfiguredAndValidForSignal
          | doc "This lambda specializes a contract for for the component based on what is defined in the pipeline and the components available in the collector"
          = fun configuredComponents type =>
            let components = std.record.fields configuredComponents in
            std.contract.custom (fun label value =>
              std.array.try_fold_left
                (fun acc e =>
                  if !std.array.elem e components then
                    'Error { message = "Defined a %{type} `%{e}` in pipeline `%{name}` is missing from the configured %{type}s", notes = components }
                  else if !std.array.elem (componentName e) ((std.record.get type (std.record.get signal knownComponents))) then
                    'Error { message = "Defined %{type} `%{e}` can't be applied to pipeline `%{name}` since it doesn't apply to signal of type `%{signal}`", notes = knownComponents."%{name}"."%{type}" }
                  else
                    'Ok value
                )
                ('Ok value)
                value
            )
        in

        let Receivers = ConfiguredAndValidForSignal (configuredReceivers & configuredConnectors) "receivers" in
        let Exporters = ConfiguredAndValidForSignal (configuredExporters & configuredConnectors) "exporters" in
        let Processors = ConfiguredAndValidForSignal configuredProcessors "processors" in

        std.contract.check { receivers | Receivers, processors | Processors | optional, exporters | Exporters, } label pipeline
      )
    in

    'Ok (
      value
      & (
        # Not a dictionary contract because we need to capture the name to drive the pipeline contract. Field is logs, metrics or traces
        value
        |> std.record.to_array
        |> std.array.map (fun e => { field = e.field, value = e.value | Pipeline (componentName e.field) })
        |> std.record.from_array
      )
    )
  )
in
{
  receivers | ComponentValidation "receivers",
  extensions | ComponentValidation "extensions" | optional,
  exporters | ComponentValidation "exporters",
  processors | ComponentValidation "processors" | optional,
  connectors | ComponentValidation "connectors" | optional,
  service
    | {
      extensions | Array String | optional,
      pipelines
        | {
          _ | {
            receivers | Array String | std.array.NonEmpty,
            processors | Array String | optional,
            exporters | Array String | std.array.NonEmpty
          }
        }
        | PipelineNames
        | PipelineContract receivers exporters processors connectors,
      telemetry | { .. }
    },
}
