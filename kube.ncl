let m = import "./k8s/v1.31.0/merge.ncl" in
let all = (import "./k8s/v1.31.0/k8s.ncl") in
let { Networking, .. } = import "types.ncl" in
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

  Kube | doc "Collection of various kubernetes types and contracts"
    = {
      Name
        | doc "Kubernetes Metadata.Name based on RFC1123, lowercase alphanumeric and '-'"
        = std.contract.from_predicate (fun name => std.string.is_match "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" name),

      ToBytes | doc "Convert Request/Limits to total bytes" | Resource -> Number
        = fun resource =>
          let allUnits = [| 'm, 'mi, 'k, 'Ki, 'M, 'Mi, 'G, 'Gi, 'T, 'Ti, 'P, 'Pi, 'E, 'Ei |] in
          let powerOf2 = std.number.pow 2 in
          let unit =
            resource
            |> std.string.characters
            |> std.array.filter (fun e => !std.string.is_match "^[0-9]*$" e)
            |> std.array.reduce_right (++) | std.enum.TagOrString | allUnits
          in
          let value =
            resource
            |> std.string.characters
            |> std.array.filter (fun e => std.string.is_match "^[0-9]*$" e)
            |> std.array.reduce_right (++)
            |> std.string.to_number
          in
          unit
          |> match {
            'k => value * 1e3,
            'M => value * 1e6,
            'G => value * 1e9,
            'T => value * 1e12,
            'P => value * 1e15,
            'E => value * 1e18,
            'm => value / 1000,
            'mi => value / 1024,
            'Ki => value * powerOf2 10,
            'Mi => value * powerOf2 20,
            'Gi => value * powerOf2 30,
            'Ti => value * powerOf2 40,
            'Pi => value * powerOf2 50,
            'Ei => value * powerOf2 60,
          },

      Resource | doc "Kubernetes compute resource, cpu and memory"
        =
          std.contract.from_predicate (fun val => std.is_number val || std.string.is_match "^[0-9]+(\\.[0-9]+)?(mi?|k|Ki|Mi?|Gi?|Ti?|Pi?|Ei?)?$" val),

      PortOrName
        | doc "Define a port either by standard port range a port name like http, grpc, etc."
        = fun label port =>
          std.typeof port
          |> match {
            'String => port | Name,
            'Number => port | Networking.Port,
            _ => std.contract.blame_with_message "Expected either a port name or port number, got neither" label,
          },

      Manifest
        | doc m%"KubeResrouce requires apiVersion, kind and metadata.name"%
        = { apiVersion | String, kind | String, metadata | { name | String, .. }, .. },

      List
        | doc m%"KubeList is a list of resources of various types"%
        = { apiVersion = "v1", kind = "List", items | Array Kube.Manifest },
    },

  Release
    | doc m%%"
      Release is the core contract and the only contract that you need to apply to your config to ensure what you are producing is a valid set of kubernetes resources.
      This is an extensible contract which allows you to add CRDs, Compute Service DNS records, Apply Overlays and Constraints without breaking any of the kubernetes resources.
    "%%
    = {
      Inputs | { .. } | optional, # This can't be validated by us, this is up to the user to decide how to use it or even better not use it
      Manifests | { _ : Kube.Manifest },
      Package
        | Kube.List
        = {
          items =
            (
              std.record.values Manifests
              |> std.array.map (fun e => Patcher Overlays e)
              |> std.array.map (fun e => Enforcer Constraints e)
            ) | ManifestsValidation Kinds
        }, # | (import "self-contained-release.ncl"),
      Dns
        | doc "Kubernetes Deployments are loosely dependent, different deployments need addressable domain to other service. This object creates the default kubernetes dns entry for each service define in manifests"
        =
          let services =
            Manifests
            |> std.record.to_array
            |> std.array.filter (fun e => e.value.kind == "Service")
          in
          services
          |> std.array.map (fun e => e.value)
          |> std.array.fold_right
            (fun s acc =>
              let domain = s.metadata.name ++ "." ++ s.metadata.namespace ++ ClusterDomain in
              let r = std.array.fold_right (fun p acc => std.record.insert p.name (domain ++ ":" ++ std.to_string p.port) acc) {} s.spec.ports in
              std.record.insert s.metadata.name r acc
            )
            {},
      Overlays | { _ | Patch } | default = {},
      Constraints
        | doc "This is a not exported field, user of its parent contract can't evaluate the nickel program on its own, that program in itself is meaningless, if you are failing and looking here export to yaml or json, the consumer of these configs are expecting json/yaml"
        | not_exported
        | { _ | Patch }
        | default
        = {},
      Kinds
        | doc "Exnteded kinds outside of the native k8 resources, adding a native k8 resource here will fail cause a failure when validating the contract"
        | not_exported
        | { _ | Kube.Manifest }
        | default
        = {},
      ClusterDomain | not_exported | String | default = ".cluster.local",
    },

  Env
    | doc "Env represents a collection of releases. This is useful when managing a fleet of application or you want to manage several releases/packages as a single unit"
    = {
      Releases | doc "Collection of the Releases, a Release is a collection of KubeResource" | { _ | Release },
      Overlays
        | doc m%%"
          Arbitrary Patches to apply to all resources in the computed environment.Overlays.
          If you need to target a specific Release use Overlays property in the orignal Release Config
        "%%
        | { _ | Patch }
        | default
        = {},
      Constraints | { _ | Patch } | default = {},

      Kinds
        | doc "Exnteded kinds outside of the native k8 resources, adding a native k8 resource here will fail cause a failure when validating the contract"
        | not_exported
        | { _ | Kube.Manifest }
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
                  e.Manifests
                  |> std.record.values
                  |> std.array.map (fun m => Patcher e.Overlays m)
                  |> std.array.map (fun m => Enforcer e.Constraints m)
                )
                |> std.array.flatten
                |> std.array.map (fun e => Patcher Overlays e)
                |> std.array.map (fun e => Enforcer Constraints e)
              ) | ManifestsValidation Kinds
          } | Kube.List | (import "self-contained-release.ncl"),
    },

  ManifestsValidation
    | doc m%%"
      Extensible contract that allows to augment the native k8 contracts and introduce your own type.
      This is already included in both Release and Env and user not expecting to use this unless they are creating their own contracts."%%
    | { _ | Kube.Manifest } -> Dyn -> Dyn
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
                let serverSideContract =
                  if std.array.length api_and_group == 1 then
                    serverSide."%{(std.array.at 0 api_and_group)}"."%{e.kind}"
                  else
                    serverSide."%{(std.array.at 0 api_and_group)}"."%{(std.array.at 1 api_and_group)}"."%{e.kind}"
                in
                (
                  e
                  & {
                    metadata.labels = {
                      "kubernetes.io/managed-by" = "nickel-k8s",
                      # TODO: annotation is more appropriate here
                      # "nickel-k8s/hash" = packageHash,
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
      let kind = resource.kind in
      let rApiVersion = std.string.split "/" resource.apiVersion in
      let group = if std.array.length rApiVersion > 1 then std.array.at 0 rApiVersion else "" in
      let version = if std.array.length rApiVersion > 1 then std.array.at 1 rApiVersion else std.array.first rApiVersion in
      let to_mergeable =
        if group != "" then
          # core apis don't have a group
          m."%{group}"."%{version}"."%{kind}".to_merge_form
        else
          m."%{version}"."%{kind}".to_merge_form
      in
      let from_mergeable =
        if group != "" then
          # core apis don't have a group
          m."%{group}"."%{version}"."%{kind}".from_merge_form
        else
          m."%{version}"."%{kind}".from_merge_form
      in

      # TODO: make overlays an array of overlays and filter those based on the matching requires
      #       i.e. match on apiVersion and kind, and then if the overlay has a name, it applies only to the matching resource
      let rName = resource.metadata.name in
      if std.record.has_field kind overlays then
        let mergableResource = to_mergeable resource in
        let mergableOverlay = to_mergeable (std.record.get kind overlays) in
        let final = mergableResource & mergableOverlay in
        from_mergeable final
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
