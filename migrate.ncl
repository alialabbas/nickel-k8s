# NOTE: this will fail on resources that doesn't respsect add namespace to their resources.
# This is really trivial and I could make the system use the true "default" namespace similar to how kube works
# But, default namespace is discouraged to be used beyond testing and prototyping.
# Also typically you organize your namespace to make some of your workload
# And also, if you truly want a computable resources that describe the state, it should not have user side input
let all =
  (import "all.yaml")
  |> std.array.fold_right
    (
      fun e acc =>
        let field = (e.metadata.name ++ "-" ++ (std.string.lowercase e.kind))
        in  std.record.insert field e acc
    )
    {}
in
{ Manifests = all }
