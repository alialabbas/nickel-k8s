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
let p = {
  spec = {
    containers = [
      {
        name = "test",
        image = "nginx",
        ports = [
          {
            containerPort = 80,
            name = "http"
          }
        ],
      }
    ]
  }
} in (p | v1.Pod | all.v1.Pod) == p
