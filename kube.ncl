# Works
# Cleaner
# The user know what data they are loading
# The only issue is this only works with the runtime generated stuff right now
# So if one wanted to create their types externally it won't work at all
let schema_utils = import "nickel-schema.ncl" in
let lib = import "lib.ncl" in
let patch = { apiVersion | String, kind | String, metadata.name | String | optional, .. } in
let CRD = {
  spec
    | {
      versions
        | Array {
          schema | { openAPIV3Schema | schema_utils.Schema, .. },
          ..
        },
      ..
    },
  ..
}
in
let ResourceMetadataHandler | { .. } -> lib.k8s.Manifest -> lib.k8s.Manifest = fun input resource =>
  resource
  & {
    # The proprity here is import to allow us to avoid conflicts with default values
    # TODO: reconsider adding the defautl namespace instead of just ignoring it. The latter would make it more clear
    # TODO: this name suffix is really indicative of the application instance to be deployed
    # This unfortunately would affect the outcome of the resources and need a way to just add an instantations based on known resources.
    metadata = {
      name | priority 2 = input.prefix ++ resource.metadata.name ++ input.suffix,
      labels = input.labels,
      annotations = input.annotations,
    }
  }
  & (if input.namespace != "" then { metadata = { namespace | priority 2 = input.namespace } } else {})
in
let EnvMetadataHandler | lib.k8s.Manifest -> { .. } -> lib.k8s.Manifest = fun input resource =>
  resource
  & {
    metadata = {
      name = input.prefix ++ resource.metadata.name ++ input.suffix,
      labels = input.labels,
      annotations = input.annotations,
    }
  }
  & (if input.namespace != "" then { metadata.namespace | priority 1 = input.namespace } else {})
in
# simple contract to ensure a patch/resource is of known group/version
# TODO: started losing context again, what is going on?
let ApiValid = fun all =>
  std.contract.custom (fun label value =>
    let kind = value.kind in
    let rApiVersion = std.string.split "/" value.apiVersion in
    let group = if std.array.length rApiVersion > 1 then std.array.at 0 rApiVersion else "" in
    let version = if std.array.length rApiVersion > 1 then std.array.at 1 rApiVersion else std.array.first rApiVersion in
    let r = if group != "" then all."%{group}" else all in
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
let ModuleInputs
  | doc "Inputs for manipulating common operation kubernetes resources"
  = {
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
in
{
  Release
    | doc m%"
      Release is the core contract and the only contract that you need to apply to your config to ensure what you are producing is a valid set of kubernetes resources.
      This is an extensible contract which allows you to add CRDs, Compute Service DNS records, Apply Overlays and Constraints without breaking any of the kubernetes resources.
    "%
    # NOTE: naked contract because we want to fail early and drop laziness when possible
    # TODO: maybe just a function and just need to figure out a way to capture the orignal input schema as is
    = fun schema =>
      std.contract.custom (fun label value =>
        let type = std.typeof schema in
        if type != 'Record then
          'Error { message = "schema should be a record, got `%{std.to_string type}`" }
        else
          let result =
            std.contract.apply
              {
                # TODO: could techincally have here a Release property which recurse itself, but that end up re-creating an infinite hierarchy which I don't want to encourage. That's why Env is its own thing so then we force declaration of manifests and then a single place to aggregate them
                Inputs | schema | optional,
                ReleaseInputs
                  | doc "Inputs for manipulating common operation kubernetes resources"
                  | ModuleInputs
                  | default
                  = {},
                Manifests
                  | { _ : lib.k8s.Manifest },
                Package
                  | lib.k8s.List
                  = {
                    items =
                      let apis = (schema_utils.k8s_schemas k8s_schema) & (schema_utils.crds_schemas crds) in
                      (
                        std.record.values Manifests
                        |> std.array.map (fun e => ResourceMetadataHandler ReleaseInputs e)
                        |> std.array.map (fun e => Patcher Overlays e apis k8s_schema)
                        |> std.array.map (fun e => Enforcer Constraints e apis)
                      ) | ManifestsValidation apis
                  },
                Overlays | Array Patch | default = [],
                Constraints
                  | doc "This is a not exported field, user of its parent contract can't evaluate the nickel program on its own, that program in itself is meaningless, if you are failing and looking here export to yaml or json, the consumer of these configs are expecting json/yaml"
                  | not_exported
                  | Array Patch
                  | default
                  = [],
                k8s_schema
                  | doc "k8s version to test against"
                  | { definitions | { _ | schema_utils.Schema }, .. },
                crds
                  | doc "crds to generate their definitions and link to the template"
                  | Array CRD
                  | default
                  = [],
              }
              label
              value
          in
          'Ok result
      ),

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

      ReleaseInputs
        | doc "Global Env Overrides that would apply to all resources, this is applied after the individual reslease overrides "
        | ModuleInputs
        | optional,
      k8s_schema
        | doc "k8s version to test against"
        | { definitions | { _ | schema_utils.Schema }, .. },
      crds
        | doc "crds to generate their definitions and link to the template"
        | Array CRD
        | default
        = [],

      Package
        | doc m%%"
          Env is a computed field which applies all overlays/patches from the original included release.
          It also applying environment specific overlays and patches"%%
        =
          {
            items =
              let apis = (schema_utils.k8s_schemas k8s_schema) & (schema_utils.crds_schemas crds) in
              (
                Releases
                |> std.record.values
                |> std.array.map (fun e =>
                  # NOTE: Manifests is used because Contract Fields are carried over even when not defined
                  # This would cause the next manifest validation to fail on many mutual exclusion tests
                  e.Manifests
                  |> std.record.values
                  |> std.array.map (fun m => ResourceMetadataHandler e.ReleaseInputs m)
                  |> std.array.map (fun m => Patcher e.Overlays m apis k8s_schema)
                  |> std.array.map (fun m => Enforcer e.Constraints m apis)
                )
                |> std.array.flatten
                |> std.array.map (fun e => EnvMetadataHandler ReleaseInputs e)
                |> std.array.map (fun e => Patcher Overlays e apis k8s_schema)
                |> std.array.map (fun e => Enforcer Constraints e apis)
              ) | ManifestsValidation apis
          } | lib.k8s.List, # | (import "self-contained-release.ncl"),
    },

  # TODO: should be a function and not a contract
  ManifestsValidation
    | doc m%%"
      Extensible contract that allows to augment the native k8 contracts and introduce your own type.
      This is already included in both Release and Env and user not expecting to use this unless they are creating their own contracts."%%
    | { _ | lib.k8s.Manifest } -> Dyn
    = fun all =>
      std.contract.custom (fun label value =>
        let serverSide = (import "all.ncl") in
        let type = std.typeof value in
        type
        |> match {
          'Array =>
            'Ok (
              std.array.map
                (fun e =>
                  let api_and_group = std.string.split "/" e.apiVersion in
                  let clientSideContract =
                    # TODO: this part is used a lot, need a wrapper around it
                    if std.array.length api_and_group == 1 then
                      all."%{(std.array.at 0 api_and_group)}"."%{e.kind}"
                    else
                      all."%{(std.array.at 0 api_and_group)}"."%{(std.array.at 1 api_and_group)}"."%{e.kind}"
                  in
                  let serverSideContract = # TODO: server side should be optional only when it exists
                    if std.array.length api_and_group == 1 then
                      serverSide."%{(std.array.at 0 api_and_group)}"."%{e.kind}"
                    else
                      lib.records.get_value_at_path [(std.array.at 0 api_and_group), (std.array.at 1 api_and_group), e.kind] serverSide
                      |> match {
                        'NotFound => Dyn,
                        _ => serverSide."%{(std.array.at 0 api_and_group)}"."%{(std.array.at 1 api_and_group)}"."%{e.kind}",
                      }
                  in
                  e | serverSideContract | clientSideContract
                )
                value
            ),
          # 'Record => std.array.all(fun e => let contract = std.record.get e.kind allContracts in std.contract.apply contract e label),
          _ => 'Error { message = "Expected an array of manifests" }
          # _ => std.contract.blame_with_message "Have you applied this to the wrong type, this work only with Array KubeResources or {_ : KubeResource }" label
        }
      ),

  ApiGroups | doc "contract to convert { _ : Kube.Resource} to { _ : Kube.Resource } grouped by apiGroup" = fun label value =>
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
    | Array Patch -> lib.k8s.Manifest -> { _ | Dyn } -> Dyn -> lib.k8s.Manifest
    = fun overlays resource apis k8s =>
      let ApiValid = ApiValid apis in
      let resource = resource | ApiValid in
      let merge_specs = (import "merge.ncl") & { Input = k8s } in
      let merge_specs = merge_specs.Output in
      let merge_utils = (import "merged.ncl") in
      let kind = resource.kind in
      let rApiVersion = std.string.split "/" resource.apiVersion in
      let group = if std.array.length rApiVersion > 1 then std.array.at 0 rApiVersion else "" in
      let version = if std.array.length rApiVersion > 1 then std.array.at 1 rApiVersion else std.array.first rApiVersion in
      let to_mergeable =
        if group != "" then
          # core apis don't have a group
          lib.records.get_value_at_path [group, version, kind] merge_specs
          |> match {
            'NotFound => fun value => value,
            _ => merge_utils.to_merge_form merge_specs."%{group}"."%{version}"."%{kind}",
          }
        else
          lib.records.get_value_at_path [version, kind] merge_specs
          |> match {
            'NotFound => fun value => value,
            _ => merge_utils.to_merge_form merge_specs."%{version}"."%{kind}"
          }
      in
      let from_mergeable =
        if group != "" then
          # core apis don't have a group
          lib.records.get_value_at_path [group, version, kind] merge_specs
          |> match {
            'NotFound => fun value => value,
            _ => merge_utils.from_merge_form merge_specs."%{group}"."%{version}"."%{kind}"
          }
        else
          merge_utils.from_merge_form merge_specs."%{version}"."%{kind}"
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
      in if std.array.length overlays > 0 then from_mergeable merged else resource,

  Enforcer
    | doc "Dynamically apply a contract on a list of resources"
    | Array Patch -> lib.k8s.Manifest -> { _ | Dyn } -> lib.k8s.Manifest
    = fun contraints resource apis =>
      std.array.fold_right
        (fun e acc =>
          let e = e | ApiValid apis in
          if e.apiVersion == resource.apiVersion && e.kind == resource.kind then
            acc | e
          else
            acc
        )
        resource
        contraints,
}
