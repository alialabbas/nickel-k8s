let { HorizontalPodAutoscaler, .. } = import "./workload-management.ncl" in
{
  metadata = {
    name = "test"
  },
  spec = {
    minReplicas = 10,
    maxReplicas = 100,
    scaleTargetRef = {
      kind = "Deployment",
      name = "testy",
    },
    behavior = {
      scaleDown = {
        stabilizationWindowSeconds = 300,
        policies = [
          {
            type = "Percent",
            value = 100,
            periodSeconds = 15,
          },
        ],
      },
      scaleUp = {
        stabilizationWindowSeconds = 0,
        policies = [
          {
            type = "Percent",
            value = 100,
            periodSeconds = 15,
          },
          {
            type = "Pods",
            value = 4,
            periodSeconds = 15,
          },
        ],
        selectPolicy = "Max",
      },
    },
  },
} | HorizontalPodAutoscaler
