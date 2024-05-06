let { Kube, .. } = import "kube.ncl" in
let patch = { apiVersion | String, kind | String, metadata.name | String | optional, .. } in
# TODO: this is broken
# The only way for this to work is if we had a construct path and path check function in nickel to get all the possible paths in the original contract Best we can do close the dictionary and the supplied constrained are captured
let collectionOfPathces
  | doc "dynamic contract to enforce all the overlays and contraints are a subset of patch"
  = fun label value =>
    if std.is_record value then
      value |> std.record.to_array |> std.array.all (fun val => std.contract.apply patch label val.value)
    else
      std.contract.blame label
  in
{
  Patch
    | doc "describe a kubenretes patch that target a manfifest by kind + metadata.name"
    = { apiVersion | String, kind | String, metadata.name | String | optional, .. },

  Constraints
    | doc "contraints are a collection of patches used to close the orignal contract of a resource"
    = collectionOfPathces,

  Overlays
    | doc "an overlay is a collection of patches that describe to merge with a resource"
    = { _ | Kube.Manifest },

  Patcher
    | doc m%"Given a list of Overlays, find the one affecting the resource based on their kind or metadata.name and merge them"%
    | Patch -> Kube.Manifest -> Kube.Manifest
    = fun overlays resource =>
      # This has to support optional overlays for when a field kind doesn't exist
      # The question now becomes how to ensure the passed overlays are truly valid for the known Contracts
      # i.e. similar to constraints, it is fine if the we have no constraints, but it is not fine if a constraints is targetting an unknown contract/type
      # TODO: this should also apply only on kind when metadata.name doesn't exist
      let rKind = resource.kind in
      let rName = resource.metadata.name in
      if std.record.has_field rKind overlays then
        resource & (std.record.get rKind overlays)
      else
        resource,

  Enforcer
  # : forall a. { _ : { apiVersion | String, kind | String, ..} } -> { apiVersion: String, kind:  String; a } -> _
    | doc "Dynamically apply a contract on a list of resources"
    | { .. } -> Kube.Manifest -> Kube.Manifest
    = fun contraints resource =>
      let rName = resource.kind in
      if std.record.has_field rName contraints then
        let contract = (std.record.get rName contraints) in
        resource | std.contract.apply contract
      else
        resource,
}
