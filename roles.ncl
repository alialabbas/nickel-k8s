let lib = import "lib.ncl" in
let PolicyRule = {
  apiGroups | Array String,
  nonResourceURLs | Array String | optional,
  resourceNames | Array String | optional,
  resources | std.array.NonEmpty | Array String,
  verbs | std.array.NonEmpty | Array String
}
in
let RoleRef = {
  apiGroup | String,
  kind | String,
  name | String,
}
in
let Subject = {
  apiGroup | String | optional,
  name | lib.k8s.Name,
  namespace | lib.k8s.Name | optional,
  kind | String
}
in
{
  v1.ServiceAccount
    | doc "Kuberntes Service Account"
    = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = lib.k8s.ResourceMetadata,
      automountServiceAccountToken | Bool | optional,
      imagePullSecrets | Array { name | String } | optional,
      ..
    },

  "rbac.authorization.k8s.io".v1 = {
    ClusterRole = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRole",
      metadata | lib.k8s.ResourceMetadata,
      aggregationRule | lib.k8sLabelSelector | optional,
      rules | Array PolicyRule | optional,
      ..
    },

    ClusterRoleBinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "ClusterRoleBinding",
      metadata | lib.k8s.ResourceMetadata,
      roleRef | RoleRef,
      subjects | Array Subject | optional,
      ..
    },

    Role = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "Role",
      metadata | lib.k8s.ResourceMetadata,
      rules | Array PolicyRule | optional,
      ..
    },

    RoleBinding = {
      apiVersion = "rbac.authorization.k8s.io/v1",
      kind = "RoleBinding",
      metadata | lib.k8s.ResourceMetadata,
      roleRef | RoleRef,
      subjects | Array Subject | optional,
      ..
    },
  },
}
