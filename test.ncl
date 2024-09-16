# NOTE: prototype for how to implement kubenretes-list-map type
# Using the map model allows you to go around some limitations with Nickel and merging lists
# This ideally should be hidden from the user and should continue to use just arrays/lists
# but since nickel doesn't have custom merge, we are allowing them to use this right now to go around the issue
let lib = import "Contracts.ncl" in
let ContainerSpec = {
  name | String | std.string.NonEmpty,
  image | doc "Container Name" | String,
  command | doc "Override Docker Entrypoint" | Array String | optional,
}
in

let BigContract = {
  initContainers | Array ContainerSpec,
  maps | not_exported = { initContainers = ["name"], },
}
in

# If we assume the data is eventually correct
# we can transform the data to whatever we want it to be.
# How to determine the previous type, I mean, it is either a string or a number, can't be other than
let fromListToMap
  | doc m%"
      Transpose Contract that allows to take define a structure is an array of records and convert it to a record based on a key
      This is useufl when you want to merge data but the underlying structure is a list
    "%
  = fun key =>
    std.contract.custom
      (
        fun label value =>
          std.typeof value
          |> match {
            'Array =>
              let acc = {} in
              std.array.try_fold_left
                (
                  fun acc e =>
                    let field = std.to_string e."%{key}" in
                    if std.record.has_field field acc then
                      'Error { message = "Found duplicated key `%{e."%{key}"}`" }
                    else
                      'Ok ({ "%{field}" = std.record.remove key e } & acc)
                )
                acc
                value,
            # we assume the record value is correct and we just leave it as is.
            # the core contract in the validation will check the concrete data once we transform it back
            'Record => 'Ok value,
            _ => 'Error { message = "Expected the data to be either formatted as a map or a list that can be converted, got instead %{std.to_string (std.typeof value)}" }
          }
      )
  in

let fromMapToList
  | doc "emulate kubenretes list-map type where a key in a list acts as the anchor for the object to allow list to be easily merged"
  = fun mergeKey =>
    std.contract.custom
      (
        fun label value =>
          'Ok (
            std.record.to_array value
            |> std.array.map
              (
                fun e =>
                  let originalFieldValue =
                    # if the string is a number, convert it back to a number since that what it was originally
                    # TODO: is there a case where the value is always going to be a string and someone present it as a number only?
                    if e.field | lib.IsContract std.string.NumberLiteral then
                      std.string.to_number e.field
                    else
                      e.field
                  in { "%{mergeKey}" = originalFieldValue } & e.value
              )
          )
      )
  in
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
in
let ContainersM =
  std.contract.all_of
    [
      (
        {
          _ | {
            env | lib.FromMapToList "name" | optional,
            ports | lib.FromMapToList "containerPort" | optional,
            ..
          }
        }
      ),
      fromMapToList "name"
    ]
in
let ContainersC =
  std.contract.all_of
    [
      (
        Array {
          env | lib.FromListToMap "name" | optional,
          ports | lib.FromListToMap "containerPort" | optional,
          ..
        }
      ),
      lib.FromListToMap "name"
    ]
in

[
  {
    env = [
      {
        name = "MY_POD_IP",
        valueFrom = {
          fieldRef = { apiVersion = "v1", fieldPath = "status.podIP", },
        },
      }
    ],
    image = "otel/opentelemetry-collector-contrib:0.0.95",
    imagePullPolicy = "IfNotPresent",
    livenessProbe = { httpGet = { path = "/", port = 13133, }, },
    name = "opentelemetry-collector",
    command = ["/otelcol-contrib", "--config=/conf/relay.yaml"],
    ports = [
      { containerPort = 6831, name = "jaeger-compact", protocol = "UDP", },
      { containerPort = 14250, name = "jaeger-grpc", protocol = "TCP", },
      { containerPort = 14268, name = "jaeger-thrift", protocol = "TCP", },
      { containerPort = 4317, name = "otlp", protocol = "TCP", },
      { containerPort = 4318, name = "otlp-http", protocol = "TCP", },
      { containerPort = 9411, name = "zipkin", protocol = "TCP", }
    ],
    readinessProbe = { httpGet = { path = "/", port = 13133, }, },
    securityContext = {},
    volumeMounts = [{ mountPath = "/conf", name = "opentelemetry-collector", }],
  },
  { image = "my-image", name = "test", }
] | ContainersC | ContainersM
