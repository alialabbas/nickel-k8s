let { k8s, numbers, arrays, records, .. } = import "lib.ncl" in

let HPAScalingRules = {
  policies
    | Array {
      periodSeconds | numbers.InRange 0 1800,
      type | std.enum.TagOrString | [| 'Percent, 'Pods |],
      value | std.number.PosNat,
    }
    | std.array.NonEmpty
    | optional,
  selectPolicy | std.enum.TagOrString | [| 'Max, 'Min, 'Disabled |] | optional,
  stabilizationWindowSeconds | numbers.InRange 0 3600 | optional,
}
in
{
  policy.v1.PodDisruptionBudget = {
    apiVersion | String | force = "policy/v1",
    kind | String | force = "PodDisruptionBudget",
    metadata | k8s.Metadata,
    spec
      | records.MutualExclusive ["maxUnavailable", "minAvailable"]
      | {
        selector | k8s.LabelSelector,
        maxUnavailable | numbers.NumberOrPercentage | optional,
        minAvailable | numbers.NumberOrPercentage | optional,
        ..
      },
    ..
  },

  autoscaling.v2.HorizontalPodAutoscaler = {
    apiVersion | String | force = "autoscaling/v2",
    kind | String | force = "HorizontalPodAutoscaler",
    metadata | k8s.Metadata,
    spec
      | {
        minReplicas | std.number.PosNat,
        maxReplicas | std.number.PosNat | std.contract.from_predicate (fun value => value >= minReplicas),
        scaleTargetRef
          | {
            kind | String,
            name | k8s.Name,
            apiVersion | String | optional
          },
        behavior
          | {
            scaleUp | HPAScalingRules | optional,
            scaleDown | HPAScalingRules | optional,
          }
          | optional,
      },
    ..
  },
}
