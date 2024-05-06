# Similar idea here for tomorrow, something that gives you the basic test against the known schema when we load things into OpenTelemetry Collector
# This focuse on the known component name the validation of PipelineConfigs
# Component checked would need to be handled differently if we want to be able to do such a thing along with potentially exposing configs for something like Loki Labeling and so on
# This contract is agnostic to the OpenTel distribution, the schema that drives the evaluation is managed independently from the code but loaded
# `otelcol components` should yield the componetns in your own distribution and you could use that instead
# The interesting challenge is converting these contracts into a json schema for CRDs that extends beyond the basic type to allow correct linting and not relying on server side validation
# The idea is give something that is openended like ConfigMap a real schema inside kubernetes with little to no effort and bashing your head against the wall
# complex validation will be hard to check but I guess something needs to give or take sometimes
# Converting to JsonSchema will be impossible when there is no hint to indicate what is the contract is trying to do like allOf, anyOf and so on
# One would say why do all of this when I can just write a schema then use that schema... Schemas are not really expressive enough to what you want to do honestly
# and also breaks what I would expect from the world aka use one system for all things configs
# TODO: this should be a proper contract so that it is more obvious where errors are coming from the generated data or from our code
# TODO: This is a good candidate for a contract.from extension to apply a contract on a field and ensure enumration on a dictionary keys
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
let signalComponent
  : String -> { exporters : Array String, receivers : Array String, processors : Array String, extensions : Array String, connectors : _ }
  # TODO: this should be a proper contract so that it is more obvious where errors are coming from the generated data or from our code| doc "Helper Util to fetch the valid component for the signal"
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

let ComponentValidation = fun component label value =>
  let component =
    component # TODO: contract method instead of applying it manually
      | std.enum.TagOrString
      | [| 'receivers, 'processors, 'exporters, 'extensions, 'connectors |]
  in
  let component = std.to_string component in
  let configuredReceivers = std.record.fields value in
  let knownComponents = std.array.map (fun e => e.name) (std.record.get component cfg) in
  if std.array.all
    (
      fun r =>
        let rName = componentName r in
        if std.array.elem rName knownComponents == false then
          std.contract.blame_with_message "%{component} `%{r}` doesn't exist in the known %{component} list [ %{std.array.fold_right (fun r acc => r ++ " " ++ acc) "" (knownComponents)}]" label
        else
          true
    )
    configuredReceivers == true then
    value
  else
    null
in

let PipelineNames = fun label value =>
  if std.record.fields value
  |> std.array.all
    (
      fun e =>
        let type = componentName e in
        if type == "logs" || type == "metrics" || type == "traces" then
          true
        else
          std.contract.blame_with_message "Invalid pipeline name `%{e}` expected [logs traces metrics] or an suffixed version of them, e.g logs/example" label
    ) == true then
    value
  else
    null
in

let PipelineContract = fun configuredReceivers configuredExporters configuredProcessors configuredConnectors label value =>
  let knownComponents = {
    logs = signalComponent "logs",
    metrics = signalComponent "metrics",
    traces = signalComponent "traces",
  }
  in

  let Pipeline = fun name label pipeline =>
    let signal = componentName name in

    let componentValidForSignal = fun name type =>
      let availableComponents = std.record.get signal knownComponents in
      std.array.elem (componentName name) ((std.record.get availableComponents type) | Array String)
    in

    # this will force me to change where this is happening
    # let configuredConnectors =
    #   if std.record.has_field "connectors" value then
    #     std.record.get "connectors" value
    #   else
    #     []
    # in
    # TODO: this doesn't work for connectors and extensions
    # extensions only support receivers so those need to be captured one way in the core receivers validaation
    # connectors are special, connectors receivers and exporters. So when we check receivers we need a way to generate origina list with what maps to one as receivers and exporters basically
    let ConfiguredAndValidForSignal
      | doc "This lambda specializes a contract for for the component based on what is defined in the pipeline and the components available in the collector"
      = fun configuredComponents type label value =>
        let debugComponents = fun components => std.array.fold_right (fun r acc => r ++ " " ++ acc) "" (std.record.fields components) in
        if std.array.all
          (
            fun e =>
              if (!std.array.elem e (std.record.fields configuredComponents | Array String)) then
                std.contract.blame_with_message
                  "Defined a %{type} `%{e}` in pipeline `%{name}` is missing from the configured %{type}s [%{std.array.fold_right (fun r acc => r ++ " " ++ acc) "" (std.record.fields configuredComponents)}]"
                  label
              else if !std.array.elem (componentName e) ((std.record.get type (std.record.get signal knownComponents)) | Array String) then
                std.contract.blame_with_message
                  "Defined %{type} `%{e}` can't be applied to pipeline `%{name}` since it doesn't apply to signal of type `%{signal}`"
                  label
              else
                true
          )
          value then
          value
        else
          null
      in

    let Receivers = ConfiguredAndValidForSignal (configuredReceivers & configuredConnectors) "receivers" in
    let Exporters = ConfiguredAndValidForSignal (configuredExporters & configuredConnectors) "exporters" in
    let Processors = ConfiguredAndValidForSignal configuredProcessors "processors" in

    pipeline | { receivers | Receivers, processors | Processors | optional, exporters | Exporters, }
  in

  value
  & (
    value
    |> std.record.to_array
    |> std.array.map (fun e => { field = e.field, value = e.value | Pipeline (componentName e.field) })
    |> std.record.from_array
  )
in
# Components is always computable, the config of how it looks like under certain subsection is not. telemetry went through some iteration in the past
# If we have an ever changing schema that constantly change, how do you make something work side by side to compute the deltas of what is to be applied for a specific version only
# i.e. rather than rewriting the whole thing, we write incremental patches that would add to it. This work only if the schema is addiditive.
# Which I guess from a design PoV, a break change should be a major increment on the schema, patch is truly a patch were we add to it.
{
  # TODO: this contract can be exported to allow you to do about anything you want, show an example of how one could address a complex schema like OpenTel without relying on arbitrary schema generation but rather isolated contracts similar to the kind test.....PipelineNames
  # The components name is always generated correctly from the output of otelcol components
  # Then the fine grained contract for the component is there to be applied for each component, same thing those could be looked up
  # Then the final stage of validation is the correctness of the outcome of the component.
  # - Think for example label loki data
  # - Or maybe remove attribute and you want to make the intention clear
  # - maybe you wanted to drop/aggregate
  # TODO: this name of sounds good in theory but will fail because it will cause an infinite recursion
  # Could be a good feature to have since a lot of times you want to do something like OneOf in isolation but reference the original name
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
        # TODO: change this because it captures the values and it can't just validate based on what is passed as potential optional
        | PipelineContract receivers exporters processors connectors,
      telemetry | { .. }
    },
}
