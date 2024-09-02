# NOTE: prototype for how to implement kubenretes-list-map type
# Using the map model allows you to go around some limitations with Nickel and merging lists
# This ideally should be hidden from the user and should continue to use just arrays/lists
# but since nickel doesn't have custom merge, we are allowing them to use this right now to go around the issue
let ContainerSpec = {
  name | String | std.string.NonEmpty,
  image | doc "Container Name" | String,
  command | doc "Override Docker Entrypoint" | Array String | optional,
}
in

let fromMapToList
  | doc "emulate kubenretes list-map type where a key in a list acts as the anchor for the object to allow list to be easily merged"
  = fun mergeKey coreContract map =>
    (std.record.to_array map |> std.array.map (fun e => { "%{mergeKey}" = e.field } & e.value)) | Array coreContract
  in
# We want a contract that can take an arbitrary name of a key to be the mergable key, aka the transpose key from a map to a list
# The interesting thing would be to make it so that there is a simple aggregator of sort based on resources
# With the current implemeentation it is really just a map transformation, taking x to y from the package/manifests to something else
# The transformation woudl be useful for two things
# 1. I don't need to define the name and it is taken as the thing to apply
# 2. It can help when you want to really apply an aggregation of an environment and want to look up all resources in the environment to find what you want.
# 3. This inverse if not computed from manifests, it would be very hard to find all of this stuff cohrently
# This is a conversion contract, unless I can hook to the serialization it has to be this way
# This has to be always the latest and if a user doesn't define the arrays as a map, we will need to convert them ourselves
# It should be possible with a simple method honestly that would do it
let ListOrMapOnKey
  | doc m%"
Special contract that simulate kubernetes x-kubernetes-patch-merge-key
The implementation is not kubernetes specific. Given an array of an object, define a key in the contract that can be used to represent the list as a map.
```
"%
  = fun key contract label value =>
    std.typeof value
    |> match {
      '"Array" => value,
      'Record => fromMapToList key contract value,
      _ => std.contract.blame_with_message "Invalid Type, Was expecting an array or a map" label,
    }
  in

let Containers = ListOrMapOnKey "name" ContainerSpec in
let mergeKey = "name" in
let sideCar = {
  side-car = {
    image = "redis-exporter",
  },
}
in
let testData = {
  first-name = {
    image = "redis",
  },
}
# basically if the data is transformed we are fucked.
# meaning the patching needs to happen before the data tranformation happens
# once the data is tranformed we are fucked since we can't override arrays at all
# With what we have done in release. The user never specifies the value. We are actaully overriding the manifests
# The user should consume Release.Package, that's the read to deploy manifests
# This allow the injection and overriding of containres or ports pretty easily
# It just becomes a matter of best practices until there is a proper merge function from nickel itself
# One crazy option is to go the extra mile to grok what data someone is to run a toMapFromList function or something
# This basically allow the flexiblility to write in both pattern. Heck even that patch could be magically transposed
# The issue with Transposing Patches it would require the user to do something that they are not aware of
# Is it even possible to have something a method that wraps the contract with yet another contract
# Maybe, the patch should always include the type, but could potentially also return a contract
# Thinking out loud now, patches at a global level make sense for things that would do something like adding labels or increasing min replicas for a set of resources and so on.
# for somethindg that act on containers the user should prefer to always use the Overlays of the package.
# If the overlay of the system can do it will be available in the env
# The issue is an idiot can do something stupid like overriding a container from a Deployment targetting a container with name that could be duplicated potentially
# Can't protect stupid all the time. It should attempt to apply
# And also we need to separate the environments from different invocations by different static labels or maybe offload that to helm
in
let { Records, .. } = import "Contracts.ncl" in
{
  first = 1,
  second = 1,
  record = { first = { first = "first" } }
}
  | Records.IsRecord
    {
      first = Number,
      second = Number,
      record = { first = { first = String } }
    }
