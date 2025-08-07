let schema_utils = import "nickel-schema.ncl" in
let lib = import "lib.ncl" in
let Patch = { apiVersion | String, kind | String, metadata | { name | String | optional, .. } | optional, .. } in
let CRD = {
  apiVersion | force = "apiextensions.k8s.io/v1",
  kind | force = "CustomResourceDefinition",
  spec
    | {
      versions
        | std.array.NonEmpty
        | Array {
          name | String,
          schema | { openAPIV3Schema | schema_utils.Schema, .. },
          ..
        },
      ..
    },
  ..
}
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
let ApiValid = fun all =>
  std.contract.custom (fun label value =>
    if !std.record.has_field value.apiVersion all then
      'Error { message = "Invalid apiVersion `%{value.apiVersion}`", notes = std.record.fields all }
    else if !std.record.has_field value.kind all."%{value.apiVersion}" then
      'Error { message = "Invalid kind in Patch `%{value.kind}`", notes = std.record.fields all."%{value.apiVersion}" }
    else
      'Ok value
  )
in

let generate_merge_spec
  | doc m%"
Generate a merge spec which allow transforming a k8 resource into a different format that is more suitable to use with Nickel built-in merge operator.

Nickel doesn't allow defining a custom merge function but we can work around it by transforming arrays in to records that are suitable to use with (&) operator. Fortunately, k8s have a well defined openapi extension `x-kubernetes-list-map-keys` that defines how array values should be merged. The merge spec is just a way to allow evalutors to switch between two forms, array -> records and records -> array.

# Example

A container in a pod is typically defined as

```nickel
{
  image = "some-image",
  name = "some-name",
  envs =  [
  {
  name = "SOME_VAR",
  value = "SOME_VAL",
  }]
}
```

And from the spec, an evaluator can transform the container object into a model that allow it to be merged natively using (&) operator.

```nickel
{
  image = "some-image",
  name = "some-name",
  envs =  {
    "SOME_VAR" = { value = "SOME_VAL" },
  }
}
```

This what allows the build/package system in this module to allow end users to define a partial record and it would correctly be merged correctly. For example, given the following two definitions;

```nickel
{
  image = "some-image",
  name = "some-name",
  envs = [
    {
      name = "SOME_VAR",
      value = "SOME_VAL",
    }
  ]
}
& {
  image = "some-image",
  name = "some-name",
  envs = [
    {
      name = "SOME_VAR",
      value | priority 2 = "OVERRIDE_VAL",
    },
    {
      name = "NEW_VAR",
      value = "NEW_VAL",
    }
  ]
}
```

Would result in the following result where `SOME_VAR` is overriden and `NEW_VAR` is injected into the environment variables for the container.

```nickel
{
  image = "some-image",
  name = "some-name",
  envs = [
    {
      name = "SOME_VAR",
      value | priority 2 = "OVERRIDE_VAL",
    },
    {
      name = "NEW_VAR",
      value = "NEW_VAL",
    }
  ]
}
```
"%
  = fun schema =>
    let get_ref
      | (String -> String)
      = fun ref =>
        let ref = std.string.split "/" ref in
        ref
        |> match {
          ["#", "definitions", ..rest] => std.array.first rest,
          ["#", "defs", ..rest] => std.array.first rest
        }
    in

    let rec get_paths = fun value =>
      value
      |> std.record.to_array
      |> std.array.fold_right
        (fun e acc =>
          # we always have to expand the ref first because it's value is string but technically it references a record we want to inline in the final result
          if e.field == "$ref" then
            acc
            @ (get_paths schema.definitions."%{get_ref e.value}")
          else if std.typeof e.value == 'Record
          && (std.record.has_field "x-kubernetes-list-type" e.value)
          && (e.value.x-kubernetes-list-type == "map") then
            [
              {
                field = e.field,
                value = (std.array.first e.value.x-kubernetes-list-map-keys),
                nested = (
                  std.array.map
                    (fun p =>
                      { field = p.field, value = p.value, nested = [] }
                    )
                    (get_paths e.value)
                )
              }
            ]
            @ acc
          else if std.typeof e.value != 'Record then
            acc
          else
            acc
            @ (
              std.array.map
                (fun p =>
                  if e.field == "properties" || e.field == "items" then
                    p
                  else
                    { field = "%{e.field}." ++ p.field, value = p.value, nested = std.record.get_or "nested" [] p }
                )
                (get_paths e.value)
            )
        )
        []
    in
    schema.definitions
    |> std.record.filter (fun e v => std.record.has_field "x-kubernetes-group-version-kind" v)
    |> std.record.filter (fun e v => !std.string.contains "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1" e)
    |> std.record.to_array
    |> std.array.fold_right
      (fun e acc =>
        let groupDef = std.array.first e.value.x-kubernetes-group-version-kind in
        let paths = get_paths e.value in
        let root = if groupDef.group == "" then "%{groupDef.version}" else "%{groupDef.group}/%{groupDef.version}" in
        { "%{root}"."%{groupDef.kind}" = paths } & acc
      )
      {}
in
let rec Spec = {
  field | doc "json like path to an array of record" | String,
  value | doc "an inner field inside of a record to use as an anchor to transform an array to a record" | String,
  nested | doc "Addtional fields to transform within this reference" | Array Spec
}
in
let rec _to_merge_form
  | doc m%"
  Transform a k8 model into a structure that is more suitable to work with Nickel merge semantic.
  "%
  | Array Spec -> Dyn -> Dyn
  = fun specs value =>
    # update a value in path based on its sematnic
    let rec update_path | Spec -> Dyn = fun spec original =>
      let path = std.string.split "." spec.field in
      let value = (lib.records.get_value_at_path path original) in
      let value_map =
        value
        |> match {
          'Found val => lib.k8s.from_list_to_map "%{spec.value}" val,
          _ => {}
        }
      in
      lib.records.update_value_at_path
        path
      # also update the inner values if there is a nested spec defined
        (std.record.map_values (fun e => _to_merge_form spec.nested e) value_map)
        original
    in
    std.array.fold_right update_path value specs
in
let rec _from_merge_form
  | doc "Convert back to the original k8s model"
  | Array Spec -> Dyn -> Dyn
  = fun specs value =>
    let rec update_path | Spec -> Dyn = fun spec original =>
      let path = std.string.split "." spec.field in
      let value_map =
        lib.records.get_value_at_path path original
        |> match {
          'Found val => lib.k8s.from_map_to_list "%{spec.value}" val,
          _ => []
        }
      in
      lib.records.update_value_at_path
        path
      # also update the inner values if there is a nested spec defined
        (std.array.map (fun e => _from_merge_form spec.nested e) value_map)
        original
    in
    std.array.fold_right update_path value specs
in
{
  build
    | doc m%"
  Build a release or a collection of releases as a deployment unit.

  Allows a set of transformation to happen globally on the whole unit or part of it.
  "%
    | Env -> lib.k8s.List
    = fun env =>
      {
        items =
          let crds_from_manifests =
            env.releases
            |> std.record.values
            |> std.array.map (fun e =>
              e.manifests
              |> std.record.values
              |> std.array.filter (fun e => e.kind == "CustomResourceDefinition")
            )
            |> std.array.flatten
          in
          let extractedSchemas = env.crds @ crds_from_manifests in
          let all = env.k8s_schema & (contracts.crds_to_swagger extractedSchemas) in
          let apis = (contracts.gen_k8s all) in
          let merge_specs = generate_merge_spec all in
          let merge_utils = { from_merge_form = _from_merge_form, to_merge_form = _to_merge_form } in
          let patcher = Patcher apis merge_utils merge_specs in
          (
            env
            |> merge_metadata
            |> std.record.get "releases"
            |> std.record.values
            |> std.array.map (fun e =>
              e.manifests
              |> std.record.values
              |> std.array.map (fun m => let overlays = merge_overlays_metadata (e.release_metadata & env.env_metadata) (e.overlays @ env.overlays) in patcher overlays m)
              |> std.array.map (fun m => Enforcer (e.constraints @ env.constraints) m apis)
            )
            |> std.array.flatten
          ) | Array (KubeResource apis) # | (import "self-contained-release.ncl")
      },

  Release
    | doc m%"
      Release is a collection of K8 resources that can represent an app or multiple apps. This represent what the end user will consume to generate the resources based on the release input.

      `Inputs` is a user defined schema for the resource, this is intended to be minimal and should only contain options that affect the app directly like AppConfiguration. Mutations like
      additional annotations, labels or podAffinity should always be deffered to the build step either through customized release_metadata or Overlays.

      `manifests` a dictionary of all the resources that compose an app/release.

      # Example

      ```nickel multiline
      {
        inputs | { version | String | default = "v1.0.0" } = {},
        manifests = { deployment = { apiVersion = "apps/v1/", kind = "Deployment", metadata.name = "test", spec.template.spec.containers = [{ image = "my-image:" ++ Inputs.version, name = "my-image" }] } },
      } | Release
    "%
    = {

      inputs | doc "Options to configure the resource generation when the release is instantiated." | { .. } | optional,

      output | { .. } | optional,

      release_metadata
        | doc "Inputs for manipulating common operation kubernetes resources"
        | ModuleInputs
        | default
        = {},

      manifests | doc "Dictinoary holding a the collection of resources that define an app" | { _ | lib.k8s.Manifest },
    },

  Env
    | doc "Env represents a collection of releases. This is useful when managing a fleet of application or you want to manage several releases/packages as a single unit"
    = {
      releases
        | doc "Collection of the Releases, a Release is a collection of KubeResource"
        | {
          _ | Release
          & {
            overlays | doc "List of Patches to apply to this specific release" | Array Patch | default = [],

            constraints
              | doc "This is a not exported field, user of its parent contract can't evaluate the nickel program on its own, that program in itself is meaningless, if you are failing and looking here export to yaml or json, the consumer of these configs are expecting json/yaml"
              | not_exported
              | Array Patch
              | default
              = [],
          }
        },

      overlays
        | doc m%%"
          Arbitrary Patches to apply to all resources in the computed environment.
          If you need to target a specific Release use Overlays property in the orignal Release Config
        "%%
        | Array Patch
        | default
        = [],

      constraints | doc "List of custom contracts to enforce on the environment" | Array Patch | default = [],

      env_metadata
        | doc "Global Env Overrides that would apply to all resources, this is applied after the individual reslease overrides "
        | ModuleInputs
        | default
        = {},

      k8s_schema
        | doc "k8s version to test against"
        | { definitions | { _ | schema_utils.Schema }, .. },

      crds
        | doc "crds to generate their definitions and link to the template"
        | Array CRD
        | default
        = [],
    },

  contracts = {
    gen_k8s
      | doc m%"
    Generate contracts directly from the k8s swagger definition.

    The swagger doc exist [here](https://github.com/kubernetes/kubernetes/blob/master/api/openapi-spec/swagger.json) in the offical kubernetes repo.

    It is also possible to get the definition for a live kubernetes environment with `kubectl get --raw /openapi/v2` which also definitions for all the deployed CRDs.

    # Example

    ```nickel multiline
    let apis = gen_k8s {
        swagger = "2.0",
        definitions = {
          myresource = {
            description = "Description of a hypothetical resource",
            type = "object",
            properties = {
              apiVersion = { type = "string" },
              kind = { type = "string" },
              metadata = { type = "object", additionalProperties = true,},
              spec = { type = "object", number = { type = "number" } },
            },
            x-kubernetes-group-version-kind = [
              {
                "group" = "MyGroup",
                "kind" = "MyKind",
                "version" = "v1"
              }
            ]
          }
        }
    } in
    {kind = "MyKind", apiVersion = "MyGroup/v1", metadata.name = "my-instance" } | apis."MyGroup/v1".MyKind
    ```
    "%
      = fun k8s_apidoc =>
        # we first patch schemas that are incorrect in the spec
        let fixed_schemas = {
          "io.k8s.apimachinery.pkg.util.intstr.IntOrString" = {
            oneOf = [
              {
                type = "number",
              },
              {
                type = "string",
              },
            ],
          },
          "io.k8s.apimachinery.pkg.api.resource.Quantity" = {
            "$ref" = "#/definitions/io.k8s.apimachinery.pkg.util.intstr.IntOrString"
          },
          # We can't use this as is because we default additionalProperties and start breaking many schema semantic. We rely on the contract Schema instead
          "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps" = {
            additionalProperties = true,
            type = "object",
          },
        }
        in
        let replace_schemas = fun schemas root =>
          let defs = root.definitions in
          std.record.map
            (fun k v =>
              if std.record.has_field k schemas then
                schemas."%{k}"
              else
                v
            )
            defs
        in
        # Kube Resources should always have apiVersion and kind as required with their specified resource
        # TODO: I think this could technically be written as patches and pass it to the singular patch method?
        let add_standard_required_properties = fun resourceDef =>
          let groupDef = std.array.first resourceDef.x-kubernetes-group-version-kind in
          if std.record.has_field "x-kubernetes-group-version-kind" resourceDef && std.array.length resourceDef.x-kubernetes-group-version-kind == 1 then
            let sub_schema =
              let required = (std.record.get_or "required" [] resourceDef) @ ["kind", "apiVersion", ] in
              std.record.update
                "required"
                required
                (
                  resourceDef
                  & {
                    properties = {
                      kind = {
                        const = groupDef.kind
                      },
                      apiVersion = {
                        const =
                          if groupDef.group != "" then
                            "%{groupDef.group}/%{groupDef.version}"
                          else
                            "%{groupDef.version}"
                      },
                    },
                  }
                )
            in sub_schema
          else
            resourceDef
        in
        let defs =
          replace_schemas
            fixed_schemas
            k8s_apidoc
        in
        let fix_resources_names = fun resources =>
          std.array.fold_right
            (fun e acc =>
              let def = defs."%{e.field}" in
              if std.record.has_field "x-kubernetes-group-version-kind" def
              && (std.array.length def.x-kubernetes-group-version-kind == 1) then
                let groupDef = std.array.first def.x-kubernetes-group-version-kind in
                if groupDef.group == "" then
                  acc
                  & { "%{groupDef.version}"."%{groupDef.kind}" = e.value, }
                else
                  acc
                  & { "%{groupDef.group}/%{groupDef.version}"."%{groupDef.kind}" = e.value }
              else
                acc
            )
            {}
            resources
        in
        let defs = std.record.map_values add_standard_required_properties defs in
        schema_utils.openapi_nickel { definitions = defs, swagger = "2.0" }
        |> std.record.to_array
        |> fix_resources_names,

    crds_to_swagger
      | doc m%"
      Convert a list of CRDs to an openapi definitions.

      # Example

      **NOTE: The example manifest is incomplete and only include the required fields for the contract generation.**

      ```nickel multiline
          crds_to_swagger [
            {
              apiVersion = "apiextensions.k8s.io/v1",
              kind = "CustomResourceDefinition",
              spec = {
                group = "mycustom.crd.group",
                names = {
                  kind = "MyCustomCRD",
                },
                scope = "Namespaced",
                versions = [
                  {
                    name = "v1alpha1",
                    schema = {
                      openAPIV3Schema = {
                        properties = {
                          apiVersion = { type = "string", },
                          kind = { type = "string", },
                          metadata = { type = "object", },
                          spec = { type = "number" },
                        },
                        required = ["spec"],
                        type = "object",
                      },
                    },
                  }
                ],
              },
            }
          ]
          # => { definitions = { "mycustom.crd.group.v1alpha1.MyCustomCRD" = { properties = { apiVersion = { type = 'string, }, kind = { type = 'string, }, metadata = { additionalProperties = true, type = 'object, }, spec = { type = 'number, }, }, required = ["spec"], type = 'object, x-kubernetes-group-version-kind = [{ group = "mycustom.crd.group", kind = "MyCustomCRD", version = "v1alpha1", }], }, }, swagger = "2.0", }
      ```
  "%
      | Array CRD -> Dyn
      = fun crds =>
        let add_kind_info = fun _group _kind _version resource =>
          {
            # k8s implicitly declare this object, we want to just allow anything and our contract will check for the correct properties
            properties = {
              metadata = { type = "object", additionalProperties = true, }
            },
            x-kubernetes-group-version-kind = [
              {
                group = _group,
                kind = _kind,
                version = _version
              }
            ]
          }
          & resource
        in
        let to_swagger_defs = fun crd =>
          let group = crd.spec.group in
          let kind = crd.spec.names.kind in
          std.array.fold_left
            (fun acc v =>
              let version = v.name in
              acc
              & {
                "%{group}.%{version}.%{kind}" = add_kind_info group kind version v.schema.openAPIV3Schema
              }
            )
            {}
            crd.spec.versions
        in
        crds
        |> std.array.fold_left (fun acc crd => acc & (to_swagger_defs crd)) {}
        |> (fun v => { swagger = "2.0", definitions = v }),
  },

  KubeResource
    | doc m%"
      Extensible contract that allows to augment the native k8 contracts and introduce your own type.
      This is already included in both Release and Env and user not expecting to use this unless they are creating their own contracts.
      "%
    | { _ | lib.k8s.Manifest } -> Dyn
    = fun all =>
      std.contract.custom (fun label value =>
        let serverSide = (import "all.ncl") in
        let type = std.typeof value in
        if type != 'Record then
          'Error { message = "Expected a record, got %{std.to_string type}" }
        else
          let clientSideContract =
            all."%{value.apiVersion}"."%{value.kind}"
          in
          let serverSideContract = # TODO: server side should be optional only when it exists
            lib.records.get_value_at_path [value.apiVersion, value.kind] serverSide
            |> match {
              'NotFound => Dyn,
              'Found v => v,
            }
          in
          std.contract.check
            (
              std.contract.Sequence [
                ApiValid all,
                serverSideContract,
                clientSideContract
              ]
            )
            label
            value
      ),

  Patcher
    | doc m%"Given a list of Overlays, find the one affecting the resource based on their kind or metadata.name and merge them"%
    | { _ | Dyn } -> Dyn -> Dyn -> Array Patch -> lib.k8s.Manifest -> lib.k8s.Manifest
    = fun apis merge_utils merge_specs overlays resource =>
      let ApiValid = ApiValid apis in
      let resource = resource | ApiValid in
      let kind = resource.kind in
      let to_mergeable =
        lib.records.get_value_at_path [resource.apiVersion, kind] merge_specs
        |> match {
          'NotFound => fun value => value,
          _ => merge_utils.to_merge_form merge_specs."%{resource.apiVersion}"."%{kind}",
        }
      in
      let from_mergeable =
        lib.records.get_value_at_path [resource.apiVersion, kind] merge_specs
        |> match {
          'NotFound => fun value => value,
          _ => merge_utils.from_merge_form merge_specs."%{resource.apiVersion}"."%{kind}"
        }
      in

      let overlays = std.array.filter (fun e => e.apiVersion == resource.apiVersion && e.kind == resource.kind) overlays
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
              { metadata = { labels }, .. } if is_overlay_apply_to_resource => acc & (to_mergeable e),
              { ..rest } if (!std.record.has_field "metadata" rest || rest.metadata == {}) && is_overlay_apply_to_resource => acc & (to_mergeable e),
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

  merge_metadata
    | doc m%"
 Utility function to merge metadata sources in an environment.

 The goal is to merge in a single place to ensure all references are frozen correctly and applied to where their value needs to be propagated. If a resource is using metadata.name, it needs to see what is going to be injected in the name in its manifest, ref manifests, inputs, outputs, and so on.

 # Example

 ```nickel multiline
 merge_metadata { prefix = "my-instance-", } { myapp = {apiVersion = "v1", kind = "SomeAPI", metadata.name = "myapp"} }
 # => { myapp = {apiVersion = "v1", kind = "SomeAPI", metadata.name = "my-instance-myapp",  metadata.labels = {}, metadata.annotations = {} }, }
 ```
 "%
    # NOTE: it is necessary to use map or map_values, this shouldn't be changed unless something fundementally changes in Nickel lang itself and this property is no longer true
    # The goal is to generate a record to use with (&) operator so nickel can do its job and recursively update all props correctly
    | Env -> Env
    = fun env =>
      let metadata_patch =
        env.releases
        |> std.record.map_values (fun r =>
          r
          |> std.record.map (fun k v =>
            if k == "manifests" then
              v
              |> std.record.map_values (fun m =>
                let input = env.env_metadata & r.release_metadata in
                {
                  metadata =
                    (
                      if std.record.has_field "name" m.metadata then
                        {
                          name | priority 2 = input.prefix ++ m.metadata.name ++ input.suffix,
                        }
                      else
                        {}
                    )
                    & (
                      if input.namespace != "default" then
                        { namespace | priority 1 = input.namespace }
                      else
                        {}
                    )
                    & {
                      labels = input.labels,
                      annotations = input.annotations,
                    }
                }
              )
            else
              v
          )
          |> std.record.filter (fun k v => k == "manifests")
        )
      in
      env & { releases = metadata_patch },

  merge_overlays_metadata
    | ModuleInputs -> Array Patch -> Array Patch
    = fun input manifests =>
      manifests
      |> std.array.fold_right
        (fun e acc =>
          let metadata = {
            metadata = (
              if std.record.has_field "name" (std.record.get_or "metadata" {} e) then
                {
                  name | priority 2 = input.prefix ++ e.metadata.name ++ input.suffix,
                }
              else
                {}
            )
          }
          in
          acc @ [e & metadata]
        )
        [],
}
