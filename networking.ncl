let { ResourceMetadata, Labels, .. } = import "metadata.ncl" in
let { Networking , .. } = import "types.ncl" in
let { Kube, ApiGroups, .. } = import "kube.ncl" in
let portOrProtocol = fun label value =>
  std.typeof value
  |> match {
    'String => value | Kube.Name,
    'Number => value | Networking.Port,
    _ => std.contract.blame_with_message "expected a port number or a protocol name" label,
  }
in
let svcPort = {
  appProtocol | Kube.Name | optional,
  name | Kube.Name | optional, # Only on singular svcPort
  nodePort | Networking.Port | optional,
  port | Networking.Port | optional,
  protocol | std.enum.TagOrString | [| 'TCP, 'STCP, 'UDP |] | optional,
  targetPort | portOrProtocol | optional,
}
in
{
  Service
    | doc "Kubernetes Service Object"
    = {
      apiVersion | String | force = "v1",
      kind | String | force = "Service",
      metadata | ResourceMetadata,
      spec
        | {
          allocateLoadBalancerNodePorts | Bool | optional,
          clusterIP | String | optional, # TODO: IP address need their own type
          clusterIPs | Array String | optional, # TODO: yet another special config, this need to match clusterIP on the zero-th index and also need ipFamilyPolicy when there is two, also can't use the same networking stack
          externalIPs | Array String | optional,
          externalName | Kube.Name | optional,
          externalTrafficPolicy | std.enum.TagOrString | [| 'Local, 'Cluster |] | optional,
          internalTrafficPolicy | std.enum.TagOrString | [| 'Local, 'Cluster |] | optional,
          ipFamilies | Array String | optional,
          ipFamilyPolicy | String | optional,
          loadBalanacerClass | String | optional,
          loadBalancerIP | String | optional,
          loadBalancerSourceRanges | String | optional,
          ports | Array svcPort,
          publishNotReadyAddresses | Bool | optional,
          selector | Labels | optional,
          sessionAffinity | std.enum.TagOrString | [| 'ClientIP, 'None |] | optional,
          sessionAffinityConfig | { .. } | optional, # TODO: close this contract
          type | std.enum.TagOrString | [| 'ClusterIP, 'ExternalName, 'NodePort, 'LoadBalancer |] | optional,
        },
    }
} | ApiGroups
