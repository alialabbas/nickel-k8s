let { Deployment, .. } = import "../deployment.ncl" in
let { manifests, .. } = import "./otel.ncl" in
# Right now, I see no reason to make this a full blown walker, so many edge cases
# Array simplifies it, we can type and make sure there is an error pack
# technically, the same thing record if we enforce a single level hierarcy
# manifests.x, manifest.y ===> We expect the x and the y
# the issue with a comparer method is it needs to define a forced contract to apply I think for the case of containers

# probably also to_path to make it easier for the caller to use the system
# This can't handle arrays as well, either use index based matching or just assume its not possible and err
let rec has_path = fun record path =>
  let array_path = std.string.split "." path in
  let l = std.array.length array_path in

  # base condition
  if l == 0 then
    false
  else if l == 1 then
    std.record.has_field (std.array.first array_path) record
  else if !std.record.has_field (std.array.first array_path) record then
    false
  else
    let sub_record = (std.record.get (std.array.first array_path) record) in
    has_path
      sub_record
      (
        (std.array.slice 1 l array_path)
        |> std.array.fold_right
          (fun field acc => if acc == "" then field else acc ++ "." ++ field)
          ""
      )
in

# Unfortunately this implementation can't handle record fields with special characters
# also doesn't unpack array values, those can use jq notations but it is meaningless inside nickel since they can't be modified
let rec to_path = fun record =>
  if std.typeof record != 'Record || std.record.length record == 0 then
    []
  else
    let fields = std.record.fields record in
    std.array.fold_right
      (
        fun path acc =>
          let sub_path = to_path (std.record.get path record) in
          if std.array.length sub_path == 0 then
            acc @ [path]
          else
            # std.typeof sub_path |> match {'String => ["empty"], 'Array =>["Array"], _=> ["huh?!"]}
            std.array.fold_right(fun e acc => acc @ [path ++ "." ++ e]) (acc) sub_path
            # acc @ [(std.array.fold_right (fun sub sub_acc => sub_acc ++ sub) (path ++ ".") sub_path)]
      )
      []
      fields
in

# Yeah this was a waste of tiem, this can never work, the dream of patching arrays ends here, I guess for now the inputs pattern will at least allow us to avoid this issue for a bit
# possible with extensions but not possible with overriding
# modifying existing fields will use the contract
# adding fields will cause errors, which means we need a dynamic dispatch if we do any sort of complex modification like this one
# This is why I want the basic merging method
# maybe for now, no random path stuff, pass the dotted notation or array of strings. This will make it easier to just recursively get them out one by one until it either succeed or fails
# but again that won't work because there is no ref here at all, either we directly access it or we fail.
# adding new values is simple, basic @ operatorual value
# modifying the existing ones is a pain
# again the issue is accessing the fields to get to the array to modify the act
# Ok I guess for now we wait until the custom merging is implemented
# most common releases don't need additional volumes, or volume mount
# Same thing, most won't need to add additional env unless it is specfic to an env like mimir or loki
# for those cases, we I guess someone writes the function to add what it needs to do
let patch_containers = fun deployment field =>
  (std.array.first deployment.spec.templates.spec.containers) & {}
in

let finder = fun resources kind =>
  # Would throwing the contract forces us to use kind all the time
  std.record.fields resources
  |> std.array.fold_right
    (
      fun r acc =>
        let manifest = std.record.get r resources in
        if manifest.kind == kind then
          acc & manifest
        else
          acc
    )
    {}
in
# finder manifests "deployment"
# has_path manifests "deployment.kind"
# to_path manifests.deployment.spec.template.spec
patch_containers manifests.deployment "env"
