let m = import "./k8s/v1.31.0/merge.ncl" in
let all = (import "./k8s/v1.31.0/k8s.ncl") in
let lib = import "lib.ncl" in
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
let ResourceMetadataHandler | lib.k8s.Manifest -> { .. }  -> lib.k8s.Manifest
  = fun resource input =>
    resource
    & {
      metadata = {
        name = input.prefix ++ resource.metadata.name ++ input.suffix,
        labels = input.labels,
        annotations = input.annotations,
        namespace = input.namespace
      }
    }
  in
# simple contract to ensure a patch/resource is of known group/version
let ApiValid =
  std.contract.custom (fun label value =>
    let kind = value.kind in
    let rApiVersion = std.string.split "/" value.apiVersion in
    let group = if std.array.length rApiVersion > 1 then std.array.at 0 rApiVersion else "" in
    let version = if std.array.length rApiVersion > 1 then std.array.at 1 rApiVersion else std.array.first rApiVersion in
    let r = if group != "" then m."%{group}" else all in
    if group != "" && !std.record.has_field group all then
      'Error { message = "group `%{value.apiVersion}` doesn't exist" }
    else if !std.record.has_field version r then
      'Error { message = "version `%{version}` in apiVersion is invalid" }
    else if !std.record.has_field kind r."%{version}" then
      'Error { message = "Invalid kind in Patch `%{kind}`" }
    else
      'Ok value
  )
in
{
  Release
    | doc m%"
      Release is the core contract and the only contract that you need to apply to your config to ensure what you are producing is a valid set of kubernetes resources.
      This is an extensible contract which allows you to add CRDs, Compute Service DNS records, Apply Overlays and Constraints without breaking any of the kubernetes resources.
    "%
    # NOTE: naked contract because we want to fail early and drop laziness when possible
    = fun schema label value =>
      let type = std.typeof schema in
      if type != 'Record then
        'Error { message = "schema should be a record, got `%{std.to_string type}`" }
      else
        value
          | {
            Inputs | schema | optional,
            ReleaseInputs
              | doc "Inputs for manipulating common operation kubernetes resources"
              | {
                prefix | doc "Prefix all resources with the specified string" | String | default = "",
                suffix | doc "Suffix all resources with the specified string" | default = "",
                labels
                  | doc "Adds a static set of labels to all resources, only at the top level and not on embedded resources"
                  | lib.k8s.Labels
                  | default
                  = {},
                annotations
                  | doc "Add a static set of annotations to all resources, only at the top level and not on embedded resource"
                  | lib.k8s.Annotations
                  | default
                  = {},
                namespace | doc "The namespace for the release" | String | default = "default",
              }
              | default = {},
            Manifests
              | { _ : lib.k8s.Manifest },
            Package
              | lib.k8s.List
              = {
                items =
                  (
                    std.record.values Manifests
                    |> std.array.map (fun e => ResourceMetadataHandler e ReleaseInputs)
                    |> std.array.map (fun e => Patcher Overlays e)
                    |> std.array.map (fun e => Enforcer Constraints e)
                  ) | ManifestsValidation Kinds
              }, # | (import "self-contained-release.ncl"),
            Overlays | Array Patch | default = [],
            Constraints
              | doc "This is a not exported field, user of its parent contract can't evaluate the nickel program on its own, that program in itself is meaningless, if you are failing and looking here export to yaml or json, the consumer of these configs are expecting json/yaml"
              | not_exported
              | Array Patch
              | default
              = [],
            Kinds
              | doc "Exnteded kinds outside of the native k8 resources, adding a native k8 resource here will fail cause a failure when validating the contract"
              | not_exported
              | { _ | lib.k8s.Manifest }
              | default
              = {},
          },

  Env
    | doc "Env represents a collection of releases. This is useful when managing a fleet of application or you want to manage several releases/packages as a single unit"
    = {
      # TODO: Release as the return contract from the function can be typed and reused here
      Releases | doc "Collection of the Releases, a Release is a collection of KubeResource" | { _ | (Release { .. }) },
      Overlays
        | doc m%%"
          Arbitrary Patches to apply to all resources in the computed environment.Overlays.
          If you need to target a specific Release use Overlays property in the orignal Release Config
        "%%
        | Array Patch
        | default
        = [],
      Constraints | Array Patch | default = [],

      Kinds
        | doc "Exnteded kinds outside of the native k8 resources, adding a native k8 resource here will fail cause a failure when validating the contract"
        | not_exported
        | { _ | lib.k8s.Manifest }
        | default
        = {},
      Env
        | doc m%%"
          Env is a computed field which applies all overlays/patches from the original included release.
          It also applying environment specific overlays and patches"%%
        =
          {
            items =
              (
                Releases
                |> std.record.values
                |> std.array.map (fun e =>
                  # NOTE: Manifests is used because Contract Fields are carried over even when not defined
                  e.Manifests
                  |> std.record.values
                  |> std.array.map (fun m => ResourceMetadataHandler m e.ReleaseInputs)
                  |> std.array.map (fun m => Patcher e.Overlays m)
                  |> std.array.map (fun m => Enforcer e.Constraints m)
                )
                |> std.array.flatten
                |> std.array.map (fun e => Patcher Overlays e)
                |> std.array.map (fun e => Enforcer Constraints e)
              ) | ManifestsValidation Kinds
          } | lib.k8s.List | (import "self-contained-release.ncl"),
    },

  # TODO: should be a function and not a contract
  ManifestsValidation
    | doc m%%"
      Extensible contract that allows to augment the native k8 contracts and introduce your own type.
      This is already included in both Release and Env and user not expecting to use this unless they are creating their own contracts."%%
    | { _ | lib.k8s.Manifest } -> Dyn -> Dyn
    = fun extensions label value =>
      # Operational hash to make it easier to find stale resources and delete them
      let packageHash = std.hash 'Sha256 (std.serialize 'Yaml value) in
      let extensions = extensions | ApiGroups in
      let serverSide = (import "all.ncl") in
      let allContracts = all & extensions in
      # how contracts are groked will need to change.
      # find schemaContract, find the server one and then do std.contract.Sequence here
      if extensions |> std.record.to_array |> std.array.any (fun e => std.record.has_field e.field all) then
        std.contract.blame_with_message "Can't override a core contract in the library" label
      else
        let type = std.typeof value in
        type
        |> match {
          'Array =>
            std.array.map
              (fun e =>
                let api_and_group = std.string.split "/" e.apiVersion in
                let clientSideContract =
                  if std.array.length api_and_group == 1 then
                    allContracts."%{(std.array.at 0 api_and_group)}"."%{e.kind}"
                  else
                    allContracts."%{(std.array.at 0 api_and_group)}"."%{(std.array.at 1 api_and_group)}"."%{e.kind}"
                in
                let serverSideContract = # TODO: server side should be optional only when it exists
                  if std.array.length api_and_group == 1 then
                    serverSide."%{(std.array.at 0 api_and_group)}"."%{e.kind}"
                  else
                    serverSide."%{(std.array.at 0 api_and_group)}"."%{(std.array.at 1 api_and_group)}"."%{e.kind}"
                in
                (
                  e
                  & {
                    metadata = {
                      labels = {
                        "kubernetes.io/managed-by" = "nickel-k8s",
                      },
                      annotations = {
                        "nickel-k8s/hash" = packageHash,
                      }
                    }
                  }
                ) | serverSideContract | clientSideContract #| allContracts."%{e.apiVersion}"."%{e.kind}"
              )
              value,
          # 'Record => std.array.all(fun e => let contract = std.record.get e.kind allContracts in std.contract.apply contract e label),
          _ => std.contract.blame_with_message "Have you applied this to the wrong type, this work only with Array KubeResources or {_ : KubeResource }" label
        },

  ApiGroups | doc "contract to convert { _ : Kube.Resource} to { _ : Kube.Resource } grouped by apiGroup"
    = fun label value =>
      value
      |> std.record.values
      |> std.array.fold_right
        (fun e acc =>
          { "%{e.apiVersion}" = { "%{e.kind}" = e } } & acc
        )
        {},
  Patch
    | doc "describe a kubenretes patch that target a manfifest by kind + metadata.name"
    = { apiVersion | String, kind | String, metadata | { name | String | optional, .. } | optional, .. },

  Patcher
    | doc m%"Given a list of Overlays, find the one affecting the resource based on their kind or metadata.name and merge them"%
    | Array Patch -> lib.k8s.Manifest -> lib.k8s.Manifest
    = fun overlays resource =>
      let resource = resource | ApiValid in

      let kind = resource.kind in
      let rApiVersion = std.string.split "/" resource.apiVersion in
      let group = if std.array.length rApiVersion > 1 then std.array.at 0 rApiVersion else "" in
      let version = if std.array.length rApiVersion > 1 then std.array.at 1 rApiVersion else std.array.first rApiVersion in
      let to_mergeable =
        if group != "" then
          # core apis don't have a group
          lib.records.get_value_at_path [group, version, kind] m
          |> match {
            'NotFound => fun value => value,
            _ => m."%{group}"."%{version}"."%{kind}".to_merge_form,
          }
        else
          lib.records.get_value_at_path [version, kind] m
          |> match {
            'NotFound => fun value => value,
            _ => m."%{version}"."%{kind}".to_merge_form
          }
      in
      let from_mergeable =
        if group != "" then
          # core apis don't have a group
          m."%{group}"."%{version}"."%{kind}".from_merge_form
        else
          m."%{version}"."%{kind}".from_merge_form
      in

      let merged = (
        std.array.fold_right
          (fun e acc =>
            let e = e | ApiValid in
            let is_overlay_apply_to_resource = e.apiVersion == resource.apiVersion && e.kind == resource.kind in
            let overlay_has_name = std.record.has_field "name" (std.record.get_or "metadata" {} e) in
            let is_over_matching_name = e.metadata.name == resource.metadata.name in
            e
            |> match {
              { metadata = { name }, .. } if is_over_matching_name && is_overlay_apply_to_resource => acc & (to_mergeable e),
              # TODO: add label checking, the issue with matching on labels is how do you deal with injecting them
              # i.e. match all deployment with a given label pair, then how do we also override all deployments to add once specific label
              # This bigs the question around how to apply blanket manipulation on all data trivially
              # I want to get a module and prefix all resources names because I am using it twice under two separate contexts
              # name, labels, annotations, all of those could have a simple metadata input
              { metadata = { labels }, .. } if is_overlay_apply_to_resource => acc & (to_mergeable e),
              { ..rest } if !std.record.has_field "metadata" rest && is_overlay_apply_to_resource => acc & (to_mergeable e),
              _ => acc,
            }
          )
          (to_mergeable resource)
          overlays
      )
      in from_mergeable merged,

  Enforcer
    | doc "Dynamically apply a contract on a list of resources"
    | Array Patch -> lib.k8s.Manifest -> lib.k8s.Manifest
    = fun contraints resource =>
      std.array.fold_right
        (fun e acc =>
          let e = e | ApiValid in
          if e.apiVersion == resource.apiVersion && e.kind == resource.kind then
            acc | e
          else
            acc
        )
        resource
        contraints,
}
