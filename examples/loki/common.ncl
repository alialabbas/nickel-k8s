let utils = import "./utils.ncl" in
let t = import "../../transfomers.ncl" in
fun version ns config =>
  let
    _selectors = utils.component_selectors "distributor",
    _labels = utils.common_labels version "distributor",
  in
  {
    configmap = {
      apiVersion = "v1",
      data = {
        # TODO: this need a contract validation for the config itself
        # TODO: doc-generator in their respective repo should allow us to have a schema
        # The only issue is binding it to a specific version, unlike dotnet we can't load an assembly
        "config.yaml" = (std.serialize 'Yaml config)
      },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "loki",
      },
    },
    memberlist-service = {
      apiVersion = "v1",
      kind = "Service",
      metadata = {
        labels = _labels,
        name = "loki-memberlist",
      },
      spec = {
        clusterIP = "None",
        ports = [
          {
            name = "tcp",
            port = 7946,
            protocol = "TCP",
            targetPort = "http-memberlist",
          }
        ],
        selector = {
          "app.kubernetes.io/instance" = "loki",
          "app.kubernetes.io/name" = "loki",
          "app.kubernetes.io/part-of" = "memberlist",
        },
        type = "ClusterIP",
      },
    },
    runtime-configmap = {
      apiVersion = "v1",
      data = { "runtime-config.yaml" = "{}\n", },
      kind = "ConfigMap",
      metadata = {
        labels = _labels,
        name = "loki-runtime",
      },
    },
    serviceaccount = {
      apiVersion = "v1",
      automountServiceAccountToken = true,
      kind = "ServiceAccount",
      metadata = {
        labels = _labels,
        name = "loki",
      },
    },
    clusterrole = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRole",
      metadata = {
        labels = _labels,
        name = "loki",
      },
      rules = [
        {
          apiGroups = [""],
          resources = ["configmaps", "secrets"],
          verbs = ["get", "watch", "list"],
        }
      ],
    },
    clusterrolebinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRoleBinding",
      metadata = {
        labels = _labels,
        name = "clusterrolebinding",
      },
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io",
        kind = "ClusterRole",
        name = "clusterrole",
      },
      subjects = [
        {
          kind = "ServiceAccount",
          name = "loki",
          namespace = ns,
        }
      ],
    },
  }
