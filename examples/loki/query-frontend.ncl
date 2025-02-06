let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "query-frontend",
    _labels = utils.common_labels version "query-frontend",
    _podtemplate = utils.pod_template version "query-frontend"
  in
{
  query-frontend-deployment = {
    apiVersion = "apps/v1",
    kind = "Deployment",
    metadata = {
      labels = _labels,
      name = "query-frontend",
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
        spec = _podtemplate,
      },
    },
  },
  query-frontend-headless-service = t.HeadlessServiceForWorkload query-frontend-deployment,
  query-frontend-poddisruptionbudget = t.PodDisruptionBudgetForWorkload query-frontend-deployment ('maxUnavailable 1),
  query-frontend-service = t.ServiceFromDeployment query-frontend-deployment,
}
