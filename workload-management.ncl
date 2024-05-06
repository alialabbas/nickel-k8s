let { Metadata, LabelSelector, .. } = import "metadata.ncl" in
let { Numbers, Arrays, Records, .. } = import "types.ncl" in
let { Kube, ApiGroups, .. } = import "kube.ncl" in

let HPAScalingRules = {
  policies
    | Array {
      periodSeconds | Numbers.InRange 0 1800,
      type | std.enum.TagOrString | [| 'Percent, 'Pods |],
      value | std.number.PosNat,
    }
    | Arrays.MinItems 1
    | optional,
  selectPolicy | std.enum.TagOrString | [| 'Max, 'Min, 'Disabled |] | optional,
  stabilizationWindowSeconds | Numbers.InRange 0 3600 | optional,
}
in
{
  PodDisruptionBudget = {
    apiVersion | String | force = "policy/v1",
    kind | String | force  = "PodDisruptionBudget",
    metadata | Metadata,
    spec
      | Records.MutualExclusive ["maxUnavailable", "minAvailable"]
      | {
        selector | LabelSelector,
        maxUnavailable | Numbers.NumberOrPercentage | optional,
        minAvailable | Numbers.NumberOrPercentage | optional,
      }
  },

  HorizontalPodAutoscaler = {
    apiVersion | String | force  = "autoscaling/v2",
    kind | String | force = "HorizontalPodAutoscaler",
    metadata | Metadata,
    spec
      | {
        minReplicas | std.number.PosNat,
        maxReplicas | std.number.PosNat | std.contract.from_predicate (fun value => value >= minReplicas),
        scaleTargetRef
          | {
            kind | String,
            name | Kube.Name,
            apiVersion | String | optional
          },
        behavior
          | {
            scaleUp | HPAScalingRules | optional,
            scaleDown | HPAScalingRules | optional,
          }
          | optional,
      },
  },
} | ApiGroups
