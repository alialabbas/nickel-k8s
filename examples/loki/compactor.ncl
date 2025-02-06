let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version =>
  let
    _selectors = utils.component_selectors "compactor",
    _labels = utils.common_labels version "compactor",
    _pod_template = utils.pod_template version "compactor",
  in
  {
    compactor-statefulset = {
      apiVersion = "apps/v1",
      kind = "StatefulSet",
      metadata = {
        labels = _labels,
        name = "loki-compactor",
      },
      spec = {
        podManagementPolicy = "Parallel",
        replicas = 1,
        revisionHistoryLimit = 10,
        selector = {
          matchLabels = _selectors,
        },
        serviceName = "loki-compactor-headless",
        template = {
          metadata = {
            labels = _labels,
          },
          spec = _pod_template
        },
        updateStrategy = { rollingUpdate = { partition = 0, }, },
      },
    },
    compactor-service = t.ServiceFromDeployment compactor-statefulset,
  }
