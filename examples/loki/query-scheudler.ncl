let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "query-frontend",
    _labels = utils.common_labels version "query-frontend",
    _pod_template = utils.pod_template version "query-frontend"
  in
  {
    query-scheduler-deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata = {
        labels = _selectors,
        name = "query-scheduler",
      },
      spec = {
        replicas = 2,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = _selectors,
        },
        strategy = {
          rollingUpdate = { maxSurge = 0, maxUnavailable = 1, },
        },
        template = {
          metadata = {
            labels = _labels,
          },
          spec = _pod_template,
        },
      },
    },
    query-scheduler-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-scheduler-deployment ('maxUnavailable 1),
    query-scheduler-service = t.ServiceFromDeployment query-scheduler-deployment,
  }
