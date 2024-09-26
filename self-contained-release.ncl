let { Kube, .. } = import "kube.ncl" in
let printArray : Array String -> String = fun value => value |> std.array.fold_right (fun e acc => e ++ " " ++ acc) "" in
# The goal is to make this a series of release validation that can be applied to either Release.package or Env.env
# Both of these types are meant to allow to group resources and apply correctness contract to them
# Applying the meta self-contained contract to an independent release stops the user from being able to ever patch/interlink resources from different resources
# Think for example

# TODO: need a helper scope for manipulate KubeList and Array Kube.Manifest
# Good demo point to show how you can move away from random call stack to a much leander representive error
let getWorkloads | Array Kube.Manifest -> Array Kube.Manifest
  = fun resources =>
    resources
    |> std.array.filter (fun e => e.kind == "Deployment" || e.kind == "StatefulSet" || e.kind == "DaemonSet")
    |> std.array.map (fun e => e)
  in

let envsAreValid
  | doc m%%"Contract to ensure a KubeList is self-contained.
  Secrets referenced as environments variables either through Env or EnvFrom"%%
  = fun type envRefKey envFromRefName label value =>
    let deployments = getWorkloads value.items in
    let secretsEnvRefs
      | Array {
        name | String,
        key | String,
      }
      =
        deployments
        |> std.array.map
          (
            fun e =>
              e.spec.template.spec.containers
              |> std.array.map
                (
                  fun e =>
                    e.env
                    |> std.array.filter
                      (
                        fun e =>
                          if std.record.has_field "valueFrom" e then
                            if std.record.has_field envRefKey e.valueFrom then
                              true
                            else
                              false
                          else
                            false
                      )
                )
              |> std.array.flatten
          )
        |> std.array.flatten
        |> std.array.map (fun e => { name = e.valueFrom."%{envRefKey}".name, key = e.valueFrom."%{envRefKey}".key })
      in
    let secretEnvFromRefs
      | Array { name }
      =
        deployments
        |> std.array.map
          (
            fun e =>
              e.spec.template.spec.containers
              |> std.array.map
                (
                  fun e =>
                    if std.record.has_field "envFrom" e then
                      e.envFrom
                      |> std.array.filter
                        (
                          fun e =>
                            std.record.has_field envFromRefName e
                        )
                    else
                      []
                )
              |> std.array.flatten
          )
        |> std.array.flatten
        |> std.array.map (fun e => { name = e."%{envFromRefName}".name, })
      in
    let allSecrets = secretsEnvRefs @ secretEnvFromRefs in
    let secrets | { _ | Array String }
      =
        value.items
        |> std.array.filter (fun e => e.kind == type)
        |> std.array.map (fun e => { field = e.metadata.name, value = e.data |> std.record.fields })
        |> std.record.from_array
      in
    let isSecretValid
    #| { name | String, key | String | optional} # Contract can't be applied in this Dynamic context
    = fun s =>
      let hasKey = if std.record.has_field "key" s then std.array.elem s.key secrets."%{s.name}" else true in
      std.record.has_field s.name secrets && hasKey
    in
    if std.array.all
      (
        fun e =>
          if !isSecretValid e then
            std.contract.blame_with_message
              "%{type} `%{e.name}` referenced as an env in a workload and doesn't exist in the list of known %{type}s `[ %{printArray (std.record.fields secrets)} ]`"
              label
          else
            true
      )
      allSecrets then
      value
    else
      std.contract.blame_with_message "Uncaught contract validation, contract author as this shouldn't occur" label
  in
# This is a global release validation.
# This never expect a set number of resources or anything like that, everything is discoverable.
# Meaning, we see what the release has from releases and then we just assert the global set of validation across the board
# If one wants, they can use this to validate a whole environment to make sure all of their configurations are correctly interlinked.
# When applied to a single release, it basically means your release is portable, it doesn't expect anything beyond just the APIs existing
# TODO: to make this a true self-contained, each resource would need to be unique in its own, no cross references
# no duplicate metadata.name should be possible
# every cross reference check should try to capture the name and check for that
# TODO: try make this isolated by make it apply Parent Contract and Child Contract
# TODO: can we utilize contract validation to make easier to apply a contract on type and that type only
# This can be setup as a processing pipeline for types so then it is only what can satisify that, the other option as I said would be to apply contract, apply the second one, then apply the first again to ensure it didn't happen in the processing in the complex validation
# TODO: This can be extract to a common template for Config+Secrets, need to pass the xKeyRef for env and xRef for envFrom, the rest is common between the two
let secretEnvRefsAreValid = envsAreValid "Secret" "secretKeyRef" "secretRef" in
let configEnvRefsAreValid = envsAreValid "ConfigMap" "configMapKeyRef" "configMapRef" in
# This checks configs+volume mounts with respect to a release/env and one captured workload
# Configs are generic, they could be created by arbitrary releases so we want to make sure at least a release know of all of them or env knows of all them
# volume/volumeMounts references with respect to both configmap and secrets are self-isolated, in the sense that you can't create a volume in pod/workload without
# Volmues + VolumeMounts validation should be implemented like this
# 1- First make sure volumes + volumemounts + pvc + pv are correctly self referenced
# 2- Second volumes with configmap reference an existing configmap key
# 3- Third, volumeMounts reference a volume that is a configmap is also referencing a subpath that exist if there is one
let configsRefsAreValid = fun label value =>
  let deployments = getWorkloads value.items in
  let knownConfigs =
    value.items
    |> std.array.filter (fun e => e.kind == "ConfigMap")
    |> std.array.map (fun e => { field = "%{e.metadata.name}", value = (std.record.fields e.data) })
    |> std.record.from_array
  in
  let refConfigs =
    deployments
    |> std.array.map (fun e => e.spec.template.spec.volumes)
    |> std.array.flatten
    |> std.array.filter (fun e => std.record.has_field "configMap" e)
    |> std.array.map
      (
        fun e =>
          {
            "%{e.configMap.name}" =
              if std.record.has_field "items" e.configMap then
                e.configMap.items |> std.array.map (fun e => e.key)
              else
                []
          }
      )
  in

  let configVolumeMounts =
    deployments
    |> std.array.map (fun e => e.spec.template.spec)
    |> std.array.fold_right # Maybe array.all, each workload would be computable in isolation and validated I believe
      (
        fun e acc =>
          let volumes =
            e.volumes
            |> std.array.filter (fun v => std.record.has_field "configMap" v)
            |> std.array.map (fun e => { field = "%{e.name}", value = e.configMap.name })
            |> std.record.from_array
          in
          let volumeMounts =
            e.containers
            |> std.array.map (fun c => c.volumeMounts)
            |> std.array.flatten
            |> std.array.filter (fun v => std.record.has_field v.name volumes)
          in
          acc
          @ [
            std.array.all
              (
                fun e =>
                  if std.record.has_field "subPath" e && !std.array.elem e.subPath (knownConfigs."%{volumes."%{e.name}"}") then
                    std.contract.blame_with_message "VolumeMount `%{e.name}` references a configmap subpath `%{e.subPath}` which doesn't exist in the orignal configmap name" label
                  else
                    true
              )
              volumeMounts
          ]
      )
      []
  in

  if std.array.all
    (
      fun e =>
        let configRef = e |> std.record.fields |> std.array.first in
        let subRef = e |> std.record.to_array |> std.array.map (fun e => e.value) |> std.array.flatten in
        if !std.record.has_field configRef knownConfigs then
          std.contract.blame_with_message
            "configMap `%{configRef}` referenced in deployment doesn't exist in the list of known configmaps [ %{std.record.fields knownConfigs |> printArray}]"
            label
        else if !std.array.all
          (
            fun e =>
              if !std.array.elem e knownConfigs."%{configRef}" then
                std.contract.blame_with_message "configMap `%{configRef}` doesn't have subkey `%{e}` in its definition" label
              else
                true
          )
          subRef then
          true
        else
          true
    )
    refConfigs == true then
    value
  else
    std.contract.blame label
in

let getPodsVolumes
  # | Array PodSpec
  = fun podSpecs =>
    podSpecs
    |> std.array.map (fun e => e.volumes)
    |> std.array.flatten
    |> std.array.map (fun e => e.name)
  in

let getVolumeMounts = fun podSpecs =>
  podSpecs
  |> std.array.map (fun e => e.containers |> std.array.map (fun c => c.volumeMounts))
  |> std.array.flatten
  |> std.array.flatten
  |> std.array.map (fun e => e.name)
in

# TODO: this should be able to grab pvctemplate from stateful and convert it to our local model
# And also need to figure out how to process externally created PVC as well as part of the volumes to be mounted
let volumeMountsAreContained = fun label value =>
  let workloads = getWorkloads value.items in
  let podSpecs = workloads |> std.array.map (fun e => e.spec.template.spec) in
  let volumes = getPodsVolumes podSpecs in
  let volumeMounts = getVolumeMounts podSpecs in
  volumeMounts
in

let areAllConfigsContainedInRelease = fun label value =>
  let workloads = getWorkloads value.items in
  let podSpecs = workloads |> std.array.map (fun e => e.spec.template.spec) in

  let configVolumes =
    podSpecs
    |> std.array.map (fun e => e.volumes)
    |> std.array.flatten
    |> std.array.map (fun e => e.name)
  in

  let configVolumeMounts =
    podSpecs
    |> std.array.map (fun e => e.containers |> std.array.map (fun c => c.volumeMounts))
    |> std.array.flatten
    |> std.array.flatten
    |> std.array.map (fun e => e.name)
  in

  if configVolumeMounts
  |> std.array.all
    (
      fun e =>
        if !std.array.elem e configVolumes then
          std.contract.blame_with_message "volume `%{e}` reference in volumeMount and missing in the release" label
        else
          true
    ) then
    value
  else
    std.contract.blame_with_message "release is expected to be a self contained release containing all of its resources" label
in

let noDuplicateMetadataName = fun label value =>
  # This could be improved and aggregate a dictionary bool, false meaning the resource combo is invalid
  # This could then be iter-ed, aggregated the list of invalid spec
  let result =
    value.items
    |> std.array.fold_right
      (
        fun e acc =>
          let r = "%{e.apiVersion}/%{e.kind}/%{e.metadata.name}" in
          if std.record.has_field r acc then
            std.contract.blame_with_message "%{e.metadata.name} already exist in the list of known resources" label
          else
            acc & { "%{r}" = e.metadata.name }
      )
      {}
  in
  if std.record.length result > 0 then value else value
in

# metacontract that applies a set of validation to ensure release/env are self contained and portable
fun label value =>
  value
  |> std.contract.apply noDuplicateMetadataName label
  |> std.contract.apply secretEnvRefsAreValid label
  |> std.contract.apply configEnvRefsAreValid label
