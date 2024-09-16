{
  status
    | {
      scaleTargetKind
        | String
        | optional,
      scaleTargetGVKR
        | {
          version
            | String,
          resource
            | String,
          kind
            | String,
          group
            | String,
          ..
        }
        | optional,
      resourceMetricNames
        | (Array String)
        | optional,
      pausedReplicaCount
        | std.number.Integer
        | optional,
      originalReplicaCount
        | std.number.Integer
        | optional,
      lastActiveTime
        | String
        | optional,
      hpaName
        | String
        | optional,
      health
        | {
          _ | {
            status
              | String
              | optional,
            numberOfFailures
              | std.number.Integer
              | optional,
            ..
          }
        }
        | optional,
      externalMetricNames
        | (Array String)
        | optional,
      conditions
        | (
          Array {
            type
              | String,
            status
              | String,
            reason
              | String
              | optional,
            message
              | String
              | optional,
            ..
          }
        )
        | optional,
      compositeScalerName
        | String
        | optional,
      ..
    }
    | optional,
  spec
    | {
      triggers
        | (
          Array {
            useCachedMetrics
              | Bool
              | optional,
            type
              | String,
            name
              | String
              | optional,
            metricType
              | String
              | optional,
            metadata
              | { _ | String },
            authenticationRef
              | {
                name
                  | String,
                kind
                  | String
                  | optional,
                ..
              }
              | optional,
            ..
          }
        ),
      scaleTargetRef
        | {
          name
            | String,
          kind
            | String
            | optional,
          envSourceContainerName
            | String
            | optional,
          apiVersion
            | String
            | optional,
          ..
        },
      pollingInterval
        | std.number.Integer
        | optional,
      minReplicaCount
        | std.number.Integer
        | optional,
      maxReplicaCount
        | std.number.Integer
        | optional,
      initialCooldownPeriod
        | std.number.Integer
        | optional,
      idleReplicaCount
        | std.number.Integer
        | optional,
      fallback
        | {
          replicas
            | std.number.Integer,
          failureThreshold
            | std.number.Integer,
          ..
        }
        | optional,
      cooldownPeriod
        | std.number.Integer
        | optional,
      advanced
        | {
          scalingModifiers
            | {
              target
                | String
                | optional,
              metricType
                | String
                | optional,
              formula
                | String
                | optional,
              activationTarget
                | String
                | optional,
              ..
            }
            | optional,
          restoreToOriginalReplicaCount
            | Bool
            | optional,
          horizontalPodAutoscalerConfig
            | {
              name
                | String
                | optional,
              behavior
                | {
                  scaleUp
                    | {
                      stabilizationWindowSeconds
                        | std.number.Integer
                        | optional,
                      selectPolicy
                        | String
                        | optional,
                      policies
                        | (
                          Array {
                            value
                              | std.number.Integer,
                            type
                              | String,
                            periodSeconds
                              | std.number.Integer,
                            ..
                          }
                        )
                        | optional,
                      ..
                    }
                    | optional,
                  scaleDown
                    | {
                      stabilizationWindowSeconds
                        | std.number.Integer
                        | optional,
                      selectPolicy
                        | String
                        | optional,
                      policies
                        | (
                          Array {
                            value
                              | std.number.Integer,
                            type
                              | String,
                            periodSeconds
                              | std.number.Integer,
                            ..
                          }
                        )
                        | optional,
                      ..
                    }
                    | optional,
                  ..
                }
                | optional,
              ..
            }
            | optional,
          ..
        }
        | optional,
      ..
    },
  metadata
    | { .. }
    | optional,
  kind
    | String
    | optional,
  apiVersion
    | String
    | optional,
  ..
}
