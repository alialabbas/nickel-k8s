let lib = import "lib.ncl" in
let portOrProtocol = fun label value =>
  std.typeof value
  |> match {
    'String => value | lib.k8s.Name,
    'Number => value | lib.networking.Port,
    _ => std.contract.blame_with_message "expected a port number or a protocol name" label,
  }
in
let svcPort = {
  appProtocol | lib.k8s.Name | optional,
  name | lib.k8s.Name | optional, # Only on singular svcPort
  nodePort | lib.networking.Port | optional,
  port | lib.networking.Port | optional,
  protocol | lib.enum.StringOrEnum [| 'TCP, 'STCP, 'UDP |] | optional,
  targetPort | portOrProtocol | optional,
}
in
{
  v1.Service
    | doc "Kubernetes Service Object"
    = {
      apiVersion | String | force = "v1",
      kind | String | force = "Service",
      metadata | lib.k8s.ResourceMetadata,
      spec
        | {
          clusterIP | String | optional, # TODO: IP address need their own type
          clusterIPs | Array String | optional, # TODO: yet another special config, this need to match clusterIP on the zero-th index and also need ipFamilyPolicy when there is two, also can't use the same networking stack
          externalIPs | Array String | optional, # TODO: array of ip address
          externalName | lib.k8s.Name | optional,
          externalTrafficPolicy | lib.enum.StringOrEnum [| 'Local, 'Cluster |] | optional,
          internalTrafficPolicy | lib.enum.StringOrEnum [| 'Local, 'Cluster |] | optional,
          ipFamilies | Array String | optional,
          ipFamilyPolicy | String | optional,
          loadBalancerClass| String | optional,
          loadBalancerIP | String | optional,
          loadBalancerSourceRanges | String | optional,
          ports | Array svcPort,
          publishNotReadyAddresses | Bool | optional,
          selector | lib.k8s.Labels | optional,
          sessionAffinity | lib.enum.StringOrEnum [| 'ClientIP, 'None |] | optional,
          sessionAffinityConfig | { .. } | optional, # TODO: close this contract
          type | lib.enum.StringOrEnum [| 'ClusterIP, 'ExternalName, 'NodePort, 'LoadBalancer |] | optional,
          loadBalancerClass | String | optional,
          healthCheckNodePort | std.number.Integer | optional,
          ..
        },
        ..
    }
}
