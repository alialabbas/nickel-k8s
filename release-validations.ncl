# These are a list of validate the user can pick from and apply to their releases manually.
# These can't make any assumption on the type of package they are creating, a package could be a list of configuration
# Or it could just a deployment with no service, configmap or whatever. Hence the user will need to annotate these themslves
let dbgMsg = fun items => items |> std.array.fold_right (fun e acc => (std.to_string e) ++ " " ++ acc) "" in
let { PodSpec, .. } = import "podspec.ncl" in
# TODO: This can be in types/pods and not exposed in the final all.ncl
let PodOrPodTemplate
  | doc m%%"Contract representing a podspec in a workload (deployment, stateulfset, etc) or a Pod Manifest
            This is unsafe when exporting and only used to to allow passing a contracted object of either of those types
"%%
  = {
    apiVersion | String | optional,
    kind | String | optional,
    metadata | { labels | { .. }, .. },
    spec | PodSpec
  }
  in
{
  PortCheck
    | doc m%%"
        Given a deployment, when applied on a Service object/contract,
        ensures that all the ports referenced inside the service exist in the passed deployment"%%
    | PodSpec -> Dyn -> Dyn
    = fun spec label value =>
      let containersPort =
        spec.containers
        |> std.array.fold_right (fun container acc => acc @ container.ports) []
        |> std.array.map
          (fun ports => ports.containerPort)
      in
      let servicePorts = value.spec.ports |> std.array.map (fun e => if std.record.has_field "targetPort" e then e.targetPort else e.port) in
      if servicePorts
      |> std.array.all
        (
          fun svcPort =>
            if !std.array.elem svcPort containersPort then
              std.contract.blame_with_message
                m%"Service Port %{std.string.from_number svcPort} is missing from the predefined ContainerPorts [ %{dbgMsg containersPort}]"%
                label
            else
              true
        ) then
        value
      else
        std.contract.blame_with_message "Uncaught errors while checking container ports against service ports" label,

  ValidateServiceMatchPod
    | PodOrPodTemplate -> Dyn -> Dyn
    | doc "Contract ensuring the service can reach out the deployment on the specified ports by checking that all targetPorts exist in the container ports of any container in the pod spec"
    = fun pod label value =>
      let svcSelector = value.spec.selector |> std.record.to_array in
      let podLabels = pod.metadata.labels |> std.record.to_array in
      if svcSelector
      |> std.array.all
        (
          fun selector =>
            if !std.array.elem selector podLabels then
              std.contract.blame_with_message m%"Service Selector {%{selector.field}=%{selector.value}} is not in pods labels"% label
            else
              true
        ) then
        value
      else
        std.contract.blame_with_message "Uncaught errors while checking service selector against pod" label
}
