let { ResourceMetadata, LabelSelector, .. } = import "metadata.ncl" in
let { Arrays, .. } = import "types.ncl" in
let { Kube, ApiGroups, .. } = import "kube.ncl" in
let PolicyRule = {
  apiGroups | Array String,
  nonResourceURLs | Array String | optional,
  resourceNames | Array String | optional,
  resources | Arrays.MinItems 1 | Array String,
  verbs | Arrays.MinItems 1 | Array String
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
  name | Kube.Name,
  namespace | Kube.Name | optional,
  kind | String
}
in
{
  ServiceAccount
    | doc "Kuberntes Service Account"
    = {
      apiVersion = "v1",
      kind = "ServiceAccount",
      metadata = ResourceMetadata,
      automountServiceAccountToken | Bool | optional,
      imagePullSecrets | Array { name | String } | optional,
      ..
    },

  ClusterRole = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "ClusterRole",
    metadata | ResourceMetadata,
    aggregationRule | LabelSelector | optional,
    rules | Array PolicyRule | optional,
    ..
  },

  ClusterRoleBinding = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "ClusterRoleBinding",
    metadata | ResourceMetadata,
    roleRef | RoleRef,
    subjects | Array Subject | optional,
    ..
  },

  Role = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "Role",
    metadata | ResourceMetadata,
    aggregationRule | LabelSelector | optional,
    rules | Array PolicyRule | optional,
    ..
  },

  RoleBinding = {
    apiVersion = "rbac.authorization.k8s.io/v1",
    kind = "RoleBinding",
    metadata | ResourceMetadata,
    roleRef | RoleRef,
    subjects | Array Subject | optional,
    ..
  },
} | ApiGroups
