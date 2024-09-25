let { v1, .. } = import "./k8s/v1.31.0/mergeable.ncl" in
let all = import "./k8s/v1.31.0/mapToList.ncl" in
let outter = {
  spec
    | {
      ThisExtraFieldMakeItWork | optional,
      hostAliases | Number | optional,
      containers | Number | optional,
      ..
    }
    | optional,
  ..
}
in
let inner = {

  spec
    | {
      failure | Bool | optional,
      hostAliases
        | optional,
      containers
        | Array {
          ..
        },
      ..
    }
    | optional,
  ..
}
in
let p =
  {
    apiVersion = "v1",
    kind = "Pod",
    name = "opentelemetry-collector",
    spec.containers = [
      {
        name = "opentelemetry-collector",
        env = [
          {
            name = "deploment",
            value = "test",
          }
        ],
      },
    ],
  }
 in (p | v1.Pod | all.v1.Pod)
